import XCTest
@testable import BrowserKit

/// R31 and R33: Ghostty, Claude Code, transcode, copy path; Connect to Server.
final class ToolTests: XCTestCase {
    func testGhosttyAndClaude() {
        XCTAssertEqual(ToolCommand.terminal(at: documents),
                       ToolCommand("/usr/bin/open", ["-na", "Ghostty", "--args", "--working-directory=/Users/me/Documents"]))
        XCTAssertEqual(ToolCommand.claude(at: documents),
                       ToolCommand("/usr/bin/open", ["-na", "Ghostty", "--args", "--working-directory=/Users/me/Documents", "-e", "claude"]))
    }

    func testWorkingFolderIsASelectedFolderOrThePane() {
        let folder = item("Analysis", folder: true)
        XCTAssertEqual(ToolCommand.workingFolder(pane: documents, selection: [folder]), folder.url)
        XCTAssertEqual(ToolCommand.workingFolder(pane: documents, selection: [item("a.pdf")]), documents)
        XCTAssertNil(ToolCommand.workingFolder(pane: nil, selection: []))
    }

    func testTranscode() {
        let script = URL(fileURLWithPath: "/Users/me/.grand-line/bin/transcode")
        let files = [item("scan.heic").url, item("photo.png").url]
        XCTAssertEqual(ToolCommand.transcode(.jpeg, files, script: script).arguments, ["jpeg"] + files.map(\.path))
        XCTAssertTrue(TranscodeMode.jpeg.accepts([item("scan.heic"), item("photo.PNG")]))
        XCTAssertFalse(TranscodeMode.video.accepts([item("scan.heic")]))
        XCTAssertTrue(TranscodeMode.text.accepts([item("paper.pdf"), item("notes.docx")]))
        XCTAssertFalse(TranscodeMode.pdf.accepts([]))
        XCTAssertFalse(TranscodeMode.pdf.accepts([item("Folder", folder: true)]))
        XCTAssertEqual(TranscodeMode.allCases.map(\.rawValue), ["video", "png", "jpeg", "pdf", "text"])
        for mode in TranscodeMode.allCases { XCTAssertEqual(TranscodeMode.mode(for: mode.command), mode) }
    }

    func testCopyPath() {
        XCTAssertEqual(CopyPath.text(for: [item("a.pdf"), item("b c.pdf")]), "/Users/me/Documents/a.pdf\n/Users/me/Documents/b c.pdf")
    }

    func testServerAddresses() {
        XCTAssertEqual(ServerAddress.normalize("nas.local/share")?.absoluteString, "smb://nas.local/share")
        XCTAssertEqual(ServerAddress.normalize(" afp://backup.local ")?.scheme, "afp")
        XCTAssertNil(ServerAddress.normalize("smb://"))
        XCTAssertNil(ServerAddress.normalize("javascript://x"))
        XCTAssertEqual(ToolCommand.connect(to: "nas.local")?.arguments, ["smb://nas.local"])
    }

    func testProcessRunnerRunsATool() async throws {
        let result = try await ProcessRunner.run(ToolCommand("/bin/sh", ["-c", "echo oops >&2; exit 3"]))
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.errorText, "oops\n")
    }
}
