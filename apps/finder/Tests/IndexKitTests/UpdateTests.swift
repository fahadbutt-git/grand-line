import XCTest
@testable import IndexKit

/// Incremental updates from folder changes, as the watcher would send them.
final class UpdateTests: XCTestCase {
    private var folder = ""
    private let files = FileManager.default

    override func setUpWithError() throws {
        folder = try Fixture.folder()
        try Fixture.make("Projects/plan.md", in: folder)
        try Fixture.make("Projects/Old Name/inside.txt", in: folder)
    }

    override func tearDownWithError() throws {
        try? files.removeItem(atPath: folder)
    }

    private func built() async -> FileIndex {
        let index = FileIndex(roots: [folder])
        await index.build()
        return index
    }

    private func found(_ index: FileIndex, _ query: String) async -> [String] {
        await index.search(query).map(\.path)
    }

    func testNewFileAppears() async throws {
        let index = await built()
        try Fixture.make("Projects/budget.xlsx", in: folder)
        await index.apply([FolderChange(path: folder + "/Projects")])
        let paths = await found(index, "budget")
        XCTAssertEqual(paths, [folder + "/Projects/budget.xlsx"])
    }

    func testDeletedFileDisappears() async throws {
        let index = await built()
        try files.removeItem(atPath: folder + "/Projects/plan.md")
        await index.apply([FolderChange(path: folder + "/Projects/")])
        let paths = await found(index, "plan")
        XCTAssertTrue(paths.isEmpty)
        let count = await index.count
        XCTAssertEqual(count, 4)
    }

    func testNewFolderIsScannedInFull() async throws {
        let index = await built()
        try Fixture.make("Projects/New/Deep/deeper.txt", in: folder)
        await index.apply([FolderChange(path: folder + "/Projects")])
        let paths = await found(index, "deeper")
        XCTAssertEqual(paths, [folder + "/Projects/New/Deep/deeper.txt"])
    }

    func testRenamedFolderMovesItsContents() async throws {
        let index = await built()
        try files.moveItem(atPath: folder + "/Projects/Old Name", toPath: folder + "/Projects/New Name")
        await index.apply([FolderChange(path: folder + "/Projects")])
        let inside = await found(index, "inside")
        XCTAssertEqual(inside, [folder + "/Projects/New Name/inside.txt"])
        let old = await found(index, "old name")
        XCTAssertTrue(old.isEmpty)
    }

    func testRecursiveChangeRescansBelow() async throws {
        let index = await built()
        try Fixture.make("Projects/Old Name/second.txt", in: folder)
        await index.apply([FolderChange(path: folder, recursive: true)])
        let paths = await found(index, "second")
        XCTAssertEqual(paths, [folder + "/Projects/Old Name/second.txt"])
        let count = await index.count
        XCTAssertEqual(count, 6)
    }

    func testChangeBelowAnUnknownFolderRescansTheNearestKnownOne() async throws {
        let index = await built()
        try Fixture.make("Projects/Fresh/note.txt", in: folder)
        await index.apply([FolderChange(path: folder + "/Projects/Fresh")])
        let paths = await found(index, "note")
        XCTAssertEqual(paths, [folder + "/Projects/Fresh/note.txt"])
    }

    func testChangeOutsideTheRootsIsIgnored() async {
        let index = await built()
        let before = await index.count
        await index.apply([FolderChange(path: "/nonexistent/elsewhere")])
        let after = await index.count
        XCTAssertEqual(before, after)
    }

    func testFileReplacedByFolder() async throws {
        let index = await built()
        try files.removeItem(atPath: folder + "/Projects/plan.md")
        try Fixture.make("Projects/plan.md/inner.txt", in: folder)
        await index.apply([FolderChange(path: folder + "/Projects")])
        let plan = await index.search("plan.md")
        XCTAssertEqual(plan.first?.isFolder, true)
        let inner = await found(index, "inner")
        XCTAssertEqual(inner, [folder + "/Projects/plan.md/inner.txt"])
    }

    func testCompactionKeepsPaths() {
        var storage = Fixture.storage(["a/one.txt", "b/two.txt", "b/c/three.txt", "d/"])
        let b = storage.children(of: 0)["b"]!
        let removed = storage.remove(b)
        XCTAssertEqual(removed.count, 2)
        XCTAssertEqual(storage.liveCount, 4)
        let compact = storage.compacted()
        XCTAssertEqual(compact.count, 4)
        XCTAssertEqual(compact.removedCount, 0)
        let paths = (0..<compact.count).map { compact.path($0) }
        XCTAssertEqual(paths, ["/Index", "/Index/a", "/Index/a/one.txt", "/Index/d"])
        XCTAssertEqual(Set(compact.folderPaths().keys), ["/Index", "/Index/a", "/Index/d"])
    }
}
