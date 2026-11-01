import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import ArchiveKit

/// Tools run off the main thread with both pipes read while they run, and Stop
/// ends the tool and everything it started (N2, N22); copies of archive items
/// that were edited go to the Trash, never away (N4).
final class ChildProcessTests: XCTestCase {
    private var space: Workspace!

    override func setUpWithError() throws {
        space = try Workspace()
    }

    override func tearDown() {
        space.remove()
    }

    func testALongErrorOutputNeverStopsTheTool() async throws {
        // Far more than a pipe holds, on stderr, then on stdout.
        let script = "head -c 1048576 /dev/zero >&2; echo done"
        let output = try await ChildProcess.run("/bin/sh", ["-c", script])
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(decoding: output.output, as: UTF8.self), "done\n")
        XCTAssertEqual(output.errors.count, 1_048_576)
    }

    func testTheExitStatusAndTheBlockingForm() throws {
        let output = try ChildProcess.runAndWait("/bin/sh", ["-c", "echo oops >&2; exit 3"])
        XCTAssertEqual(output.status, 3)
        XCTAssertEqual(output.errorText, "oops\n")
        XCTAssertFalse(output.succeeded)
    }

    func testStopEndsTheToolAndWhatItStarted() async throws {
        let pidFile = space.url("child.pid")
        // The shell starts a child of its own and waits; Stop must end both.
        let script = "sleep 30 & echo $! > '\(pidFile.path)'; wait"
        let task = Task { try await ChildProcess.run("/bin/sh", ["-c", script]) }
        var child: pid_t = 0
        for _ in 0..<100 where child == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
            child = (try? String(contentsOf: pidFile, encoding: .utf8)).flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
        }
        XCTAssertGreaterThan(child, 0, "the tool started its child")
        let started = Date()
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a stopped tool reports CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        var gone = false
        for _ in 0..<100 where !gone {
            gone = kill(child, 0) != 0
            if !gone { try await Task.sleep(nanoseconds: 50_000_000) }
        }
        XCTAssertTrue(gone, "the tool's own child was stopped with it")
    }

    func testAToolThatCannotStartThrows() async {
        do {
            _ = try await ChildProcess.run("/nonexistent/tool", [])
            XCTFail("a missing tool started")
        } catch {
            XCTAssertTrue(error is ChildProcess.Failure)
        }
    }

    // MARK: Extract as a task

    func testAStoppedExtractLeavesNothingBehind() async throws {
        try space.file("src/README.md", "read me")
        let archive = try space.zip("src", to: "bundle.zip")
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let trash = space.url("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let task = Task {
            try await Archive.extract(["README.md"], from: archive, to: out) { url in
                try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
            }
        }
        task.cancel()
        _ = try? await task.value
        let left = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertTrue(left == [] || left == ["README.md"], "no hidden unpacking folder stays: \(left)")
    }

    func testExtractAsATask() async throws {
        try space.file("src/Figures/plot.png", "png")
        let archive = try space.zip("src", to: "bundle.zip")
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let made = try await Archive.extract(["Figures"], from: archive, to: out) { _ in XCTFail("nothing should go to the Trash") }
        XCTAssertEqual(made.map(\.lastPathComponent), ["Figures"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Figures"])
        XCTAssertEqual(space.text(out.appendingPathComponent("Figures/plot.png")), "png")
    }

    // MARK: Copies opened from an archive

    func testAnEditedCopyGoesToTheTrashNotAway() throws {
        try space.file("src/notes.txt", "draft")
        let archive = try space.zip("src", to: "bundle.zip")
        let root = space.url("opened")
        let trash = space.url("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let edited = try Archive.preview("notes.txt", from: archive, in: root)
        let untouched = try Archive.preview("notes.txt", from: archive, in: root)
        // Saved in an app: new content, and a new file beside it.
        try Data("my edits".utf8).write(to: edited)
        try Data("saved as".utf8).write(to: edited.deletingLastPathComponent().appendingPathComponent("notes copy.txt"))
        let removed = Archive.TemporaryFolder.clean(root) { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        XCTAssertEqual(removed, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: untouched.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted(), ["notes copy.txt", "notes.txt"])
        XCTAssertEqual(space.text(trash.appendingPathComponent("notes.txt")), "my edits", "the edits are kept")
    }

    func testAFolderWhoseEditCannotBeTrashedIsKept() throws {
        try space.file("src/notes.txt", "draft")
        let archive = try space.zip("src", to: "bundle.zip")
        let root = space.url("opened")
        let edited = try Archive.preview("notes.txt", from: archive, in: root)
        try Data("my edits".utf8).write(to: edited)
        let removed = Archive.TemporaryFolder.clean(root) { _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(space.text(edited), "my edits")
    }
}
