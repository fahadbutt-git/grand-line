import XCTest
@testable import BrowserKit

/// R5: the editable path bar and Go to Folder.
final class PathTests: XCTestCase {
    let drive = URL(fileURLWithPath: "/Users/me/Library/CloudStorage/GoogleDrive-smith@example.com/My Drive", isDirectory: true)

    func testResolvesHomeAbsoluteRelativeAndAliases() {
        XCTAssertEqual(PathInput.resolve("~", relativeTo: documents, home: home)?.path, "/Users/me")
        XCTAssertEqual(PathInput.resolve("~/Downloads/", relativeTo: documents, home: home)?.path, "/Users/me/Downloads")
        XCTAssertEqual(PathInput.resolve("/Applications", relativeTo: documents, home: home)?.path, "/Applications")
        XCTAssertEqual(PathInput.resolve("../Desktop", relativeTo: documents, home: home)?.path, "/Users/me/Desktop")
        XCTAssertEqual(PathInput.resolve("Papers", relativeTo: documents, home: home)?.path, "/Users/me/Documents/Papers")
        XCTAssertEqual(PathInput.resolve("Drive/01 Research", relativeTo: documents, home: home, aliases: ["Drive": drive])?.path,
                       drive.path + "/01 Research")
        XCTAssertEqual(PathInput.resolve("file:///Users/me/Movies", relativeTo: documents, home: home)?.path, "/Users/me/Movies")
    }

    func testCleansPastedPaths() {
        XCTAssertEqual(PathInput.resolve("\"~/My Files\"", relativeTo: documents, home: home)?.path, "/Users/me/My Files")
        XCTAssertEqual(PathInput.resolve("~/My\\ Files", relativeTo: documents, home: home)?.path, "/Users/me/My Files")
        XCTAssertNil(PathInput.resolve("   ", relativeTo: documents, home: home))
    }

    func testPathsAndNames() {
        XCTAssertEqual(PathInput.interpret("~/Downloads", relativeTo: documents, home: home), .path(URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)))
        XCTAssertEqual(PathInput.interpret("glaucoma", relativeTo: documents, home: home), .fuzzy("glaucoma"))
        XCTAssertEqual(PathInput.interpret("Drive", relativeTo: documents, home: home, aliases: ["Drive": drive]), .path(drive))
        XCTAssertNil(PathInput.interpret("", relativeTo: documents, home: home))
    }

    func testTabCompletion() {
        let children: (URL) -> [String] = { url in
            url.path == "/Users/me" ? ["Documents", "Downloads", "Desktop", "Developer"] : []
        }
        let options = PathInput.completions(for: "~/Do", relativeTo: documents, home: home, children: children)
        XCTAssertEqual(options.map(\.lastPathComponent), ["Documents", "Downloads"])
        let all = PathInput.completions(for: "~/", relativeTo: documents, home: home, children: children)
        XCTAssertEqual(all.count, 4)
    }

    func testSegmentsStartAtTheClosestShortName() {
        let folder = drive.appendingPathComponent("01 Research/_Active", isDirectory: true)
        let segments = PathSegments.segments(for: folder, home: home, aliases: ["Drive": drive])
        XCTAssertEqual(segments.map(\.title), ["Drive", "01 Research", "_Active"])
        XCTAssertEqual(segments.last?.url.path, folder.path)
        XCTAssertEqual(PathSegments.segments(for: documents, home: home).map(\.title), ["~", "Documents"])
        XCTAssertEqual(PathSegments.segments(for: URL(fileURLWithPath: "/Volumes/Backup"), home: home).map(\.title), ["/", "Volumes", "Backup"])
    }

    func testEditableText() {
        XCTAssertEqual(PathSegments.editableText(for: documents, home: home), "~/Documents")
        XCTAssertEqual(PathSegments.editableText(for: home, home: home), "~")
        XCTAssertEqual(PathSegments.editableText(for: URL(fileURLWithPath: "/tmp"), home: home), "/tmp")
    }
}
