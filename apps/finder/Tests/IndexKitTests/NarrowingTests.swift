import XCTest
@testable import IndexKit

/// Typing on from a query searches only what the shorter query matched, with the
/// same results as a search of the whole index.
final class NarrowingTests: XCTestCase {
    func testWhichQueriesNarrow() {
        func narrows(_ new: String, _ old: String) -> Bool {
            SearchQuery(new)!.narrows(SearchQuery(old)!)
        }
        XCTAssertTrue(narrows("conj", "con"))
        XCTAssertTrue(narrows("conj", "conj"))
        XCTAssertTrue(narrows("conj f", "conj"))
        XCTAssertTrue(narrows("conj fl", "conj f"))
        XCTAssertTrue(narrows("Conj", "con"), "queries are folded first")
        XCTAssertFalse(narrows("con", "conj"))
        XCTAssertFalse(narrows("cnj", "con"))
        XCTAssertFalse(narrows("conj fl", "con f"))
        XCTAssertFalse(narrows("flap", "conj"))
    }

    func testNarrowedSearchesMatchFullOnes() async {
        let paths = (0..<500).map { "Folder \($0 % 7)/" + ["Conj Flap \($0).pdf", "Lid Study - CONJ \($0)", "cornea \($0).md", "notes \($0).txt"][$0 % 4] }
        let typed = Fixture.index(paths)
        for text in ["c", "co", "con", "conj", "conj f", "conj fl", "conj flap 1"] {
            let narrowed = await typed.search(text, limit: 40).map(\.path)
            let whole = await Fixture.index(paths).search(text, limit: 40).map(\.path)
            XCTAssertEqual(narrowed, whole, text)
            XCTAssertFalse(narrowed.isEmpty, text)
        }
    }

    func testChangesToTheIndexStartAFreshScan() async throws {
        let folder = try Fixture.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try Fixture.make("a/conj one.txt", in: folder)
        let index = FileIndex(roots: [folder])
        await index.build()
        let before = await index.search("con").map(\.name)
        XCTAssertEqual(before, ["conj one.txt"])
        try Fixture.make("a/conj two.txt", in: folder)
        await index.apply([FolderChange(path: folder + "/a")])
        let after = await index.search("conj").map(\.name).sorted()
        XCTAssertEqual(after, ["conj one.txt", "conj two.txt"])
    }
}
