import XCTest
@testable import IndexKit

final class RankingTests: XCTestCase {
    func testTiersInOrder() async {
        let index = Fixture.index([
            "c/rxexpxoxrxt.txt",
            "c/myreports.txt",
            "c/annual report.pdf",
            "c/report card.pdf",
            "c/report",
        ])
        let results = await index.search("report")
        XCTAssertEqual(names(results), ["report", "report card.pdf", "annual report.pdf", "myreports.txt", "rxexpxoxrxt.txt"])
        XCTAssertEqual(results.map(\.tier), [.exact, .prefix, .wordStart, .substring, .fuzzy])
    }

    func testExactIgnoresOneExtension() {
        XCTAssertEqual(tier("report", "report.docx"), .exact)
        XCTAssertEqual(tier("report.docx", "report.docx"), .exact)
        XCTAssertEqual(tier("report", "report.final.docx"), .prefix)
        XCTAssertEqual(tier("zshrc", ".zshrc"), .wordStart)
    }

    func testCaseAndAccentsAreFolded() async {
        XCTAssertEqual(tier("RESUME", "Résumé.pdf"), .exact)
        let decomposed = "Re\u{301}sume\u{301}.pdf"
        let index = Fixture.index(["a/" + decomposed, "b/Résumé.pdf"])
        let results = await index.search("resume")
        XCTAssertEqual(results.count, 2)
        // Swift compares the two spellings as equal, so look them up by folder.
        let byPath = Dictionary(uniqueKeysWithValues: results.map { ($0.path, $0.highlights) })
        XCTAssertEqual(byPath["/Index/b/Résumé.pdf"], [0..<6])
        XCTAssertEqual(byPath["/Index/a/" + decomposed], [0..<8])
    }

    func testOpenedPathWinsTies() async {
        let index = Fixture.index(["a/notes.txt", "b/notes.txt"])
        let before = await index.search("notes")
        XCTAssertEqual(before.first?.path, "/Index/a/notes.txt")
        await index.noteOpened("/Index/b/notes.txt")
        let after = await index.search("notes")
        XCTAssertEqual(after.first?.path, "/Index/b/notes.txt")
    }

    func testOpenedFoldersWinTiesToo() async {
        let index = Fixture.index(["a/Drafts/", "b/Drafts/"])
        await index.noteOpened("/Index/b/Drafts/")
        let results = await index.search("drafts")
        XCTAssertEqual(results.first?.path, "/Index/b/Drafts")
        XCTAssertEqual(results.first?.isFolder, true)
    }

    func testTierBeatsUse() async {
        let index = Fixture.index(["a/notes.txt", "b/my notes.txt"])
        for _ in 0..<20 { await index.noteOpened("/Index/b/my notes.txt") }
        let results = await index.search("notes")
        XCTAssertEqual(names(results), ["notes.txt", "my notes.txt"])
    }

    func testShallowerWinsTies() async {
        let index = Fixture.index(["a/b/c/plan.md", "a/plan.md"])
        let results = await index.search("plan")
        XCTAssertEqual(results.map(\.path), ["/Index/a/plan.md", "/Index/a/b/c/plan.md"])
    }

    func testUsageScore() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let recent = Usage(count: 1, last: now.addingTimeInterval(-60))
        let old = Usage(count: 1, last: now.addingTimeInterval(-90 * 86_400))
        let often = Usage(count: 31, last: now.addingTimeInterval(-90 * 86_400))
        XCTAssertGreaterThan(recent.score(now: now), old.score(now: now))
        XCTAssertGreaterThan(often.score(now: now), old.score(now: now))
    }

    func testSeveralWordsMustAllMatch() async {
        let index = Fixture.index(["Glaucoma Review Notes.docx"])
        let none = await index.search("notes zebra")
        XCTAssertTrue(none.isEmpty)
        let both = await index.search("notes review")
        XCTAssertEqual(both.first?.tier, .wordStart)
    }

    func testWholePhraseHighlightsOnce() async {
        let index = Fixture.index(["Glaucoma Review Notes.docx"])
        let results = await index.search("review notes")
        XCTAssertEqual(results.first?.tier, .wordStart)
        XCTAssertEqual(results.first?.highlights, [9..<21])
    }

    func testLimitAndEmptyQuery() async {
        let index = Fixture.index((0..<30).map { "f/file \($0).txt" })
        let ten = await index.search("file", limit: 10)
        XCTAssertEqual(ten.count, 10)
        let zero = await index.search("file", limit: 0)
        XCTAssertTrue(zero.isEmpty)
        let blank = await index.search("   ")
        XCTAssertTrue(blank.isEmpty)
    }

    func testPathsAndFolders() async {
        let index = Fixture.index(["Research/Cornea/", "Research/Cornea/graft.pdf"])
        let results = await index.search("cornea")
        XCTAssertEqual(results.first?.path, "/Index/Research/Cornea")
        XCTAssertEqual(results.first?.isFolder, true)
        let graft = await index.search("graft")
        XCTAssertEqual(graft.first?.path, "/Index/Research/Cornea/graft.pdf")
        XCTAssertEqual(graft.first?.isFolder, false)
        let count = await index.count
        XCTAssertEqual(count, 4)
    }
}
