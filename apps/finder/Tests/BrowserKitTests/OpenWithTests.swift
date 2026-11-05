import XCTest
@testable import BrowserKit

/// R34: Open With reads default-apps.tsv.
final class OpenWithTests: XCTestCase {
    let table = DefaultAppsTable.parse("""
    # App name\tFile extensions it opens\tFallback app
    Document Editor\t.docx .doc .odt .rtf\tText Editor
    PDF Editor\t.pdf\tPDF Viewer
    Video Player\t.mp4 .mov .m4v .mkv\tVideo Player
    Office App\t.xlsx\t-

    broken line
    """)

    func testParsesTheTable() {
        XCTAssertEqual(table.rows.count, 4)
        XCTAssertEqual(table.rows[0].app, "Document Editor", "app names may contain spaces")
        XCTAssertEqual(table.rows[0].extensions, ["docx", "doc", "odt", "rtf"])
        XCTAssertEqual(table.rows[1].fallback, "PDF Viewer")
        XCTAssertNil(table.rows[3].fallback, "- means no fallback app")
    }

    func testAppsForAnExtension() {
        XCTAssertEqual(table.apps(for: "docx"), ["Document Editor", "Text Editor"])
        XCTAssertEqual(table.apps(for: ".PDF"), ["PDF Editor", "PDF Viewer"])
        XCTAssertEqual(table.apps(for: "mkv"), ["Video Player"], "an app that is its own fallback is listed once")
        XCTAssertEqual(table.apps(for: "xlsx"), ["Office App"], "no fallback app is listed for -")
        XCTAssertEqual(table.apps(for: "png"), [])
    }

    func testChoicesPutTheTableFirstAndSkipMissingApps() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let apps = try temp.folder("Applications")
        try temp.folder("Applications/Text Editor.app")
        try temp.folder("Applications/TextEdit.app")
        let system = [apps.appendingPathComponent("TextEdit.app"), apps.appendingPathComponent("Text Editor.app")]
        let choices = OpenWithMenu.choices(forExtension: "docx", table: table, folders: [apps], system: system)
        XCTAssertEqual(choices.map(\.name), ["Text Editor", "TextEdit"], "Document Editor is not installed")
        XCTAssertEqual(choices.map(\.isPreferred), [true, false])
    }

    func testSharedExtension() {
        XCTAssertEqual(OpenWithMenu.sharedExtension([item("a.pdf"), item("b.PDF")]), "pdf")
        XCTAssertNil(OpenWithMenu.sharedExtension([item("a.pdf"), item("b.docx")]))
    }

    func testRepositoryTableParses() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../config/grand-line/default-apps.tsv").standardizedFileURL
        try XCTSkipUnless(FileManager.default.fileExists(atPath: repo.path))
        XCTAssertFalse(DefaultAppsTable.load(repo).rows.isEmpty)
    }
}
