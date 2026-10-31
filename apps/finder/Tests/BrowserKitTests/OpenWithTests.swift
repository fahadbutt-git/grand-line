import XCTest
@testable import BrowserKit

/// R34: Open With reads default-apps.tsv.
final class OpenWithTests: XCTestCase {
    let table = DefaultAppsTable.parse("""
    # App name\tFile extensions it opens\tFallback app
    WordCraft\t.docx .doc .odt .rtf\tLibreOffice
    PdfCraft\t.pdf\tPreview
    IINA\t.mp4 .mov .m4v .mkv\tIINA

    broken line
    """)

    func testParsesTheTable() {
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[0].extensions, ["docx", "doc", "odt", "rtf"])
        XCTAssertEqual(table.rows[1].fallback, "Preview")
    }

    func testAppsForAnExtension() {
        XCTAssertEqual(table.apps(for: "docx"), ["WordCraft", "LibreOffice"])
        XCTAssertEqual(table.apps(for: ".PDF"), ["PdfCraft", "Preview"])
        XCTAssertEqual(table.apps(for: "mkv"), ["IINA"], "an app that is its own fallback is listed once")
        XCTAssertEqual(table.apps(for: "png"), [])
    }

    func testChoicesPutTheTableFirstAndSkipMissingApps() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let apps = try temp.folder("Applications")
        try temp.folder("Applications/LibreOffice.app")
        try temp.folder("Applications/TextEdit.app")
        let system = [apps.appendingPathComponent("TextEdit.app"), apps.appendingPathComponent("LibreOffice.app")]
        let choices = OpenWithMenu.choices(forExtension: "docx", table: table, folders: [apps], system: system)
        XCTAssertEqual(choices.map(\.name), ["LibreOffice", "TextEdit"], "WordCraft is not installed")
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
