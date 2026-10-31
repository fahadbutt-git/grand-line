import AppKit
import FileKit
import XCTest
@testable import BrowserKit

/// Cmd+C on a selected row, a double-click into a folder, Cmd+V: the steps
/// Nexus's `BrowserModel.copy()` and `paste(forceMove:)` take (`ClipboardFlow`
/// on the pane's state), then `TransferFlow` and the task engine, as in the
/// user journeys "copy and paste into a folder" and "paste over a taken name".
final class ClipboardFlowTests: XCTestCase {
    /// A pasteboard of the test's own, which counts its reads.
    final class Board {
        var count = 0
        var urls: [URL] = []
        var reads = 0

        var access: PasteboardAccess {
            PasteboardAccess(
                changeCount: { self.count },
                write: { self.urls = $0; self.count += 1 },
                read: { self.reads += 1; return self.urls }
            )
        }
    }

    private func queue(trashIn folder: URL) -> FileTaskQueue {
        FileTaskQueue(operations: FileOperations(trash: { url in
            let destination = folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }))
    }

    /// A pane showing `folder`, read from disk as Nexus reads it.
    private func pane(at folder: URL) throws -> PaneState {
        var state = PaneState(location: .folder(folder))
        state.load(try FolderReader.items(in: folder, showHidden: false))
        return state
    }

    /// A click on the row named `name`.
    private func selectRow(_ name: String, in state: inout PaneState) {
        let ids = state.items.filter { $0.name == name }.map(\.id)
        state.selection.set(ids, in: state.ids)
    }

    /// Opens the folder row named `name`, as a double-click does, and reads it.
    private func openFolder(_ name: String, in state: inout PaneState) throws {
        let row = try XCTUnwrap(state.items.first { $0.name == name })
        let action = state.openAction(for: [row])
        let target = try XCTUnwrap(action.navigate)
        state.navigate(to: target)
        state.load(try FolderReader.items(in: try XCTUnwrap(state.location.folderURL), showHidden: false))
    }

    private func withLog(_ temp: TempFolder, _ body: () async throws -> Void) async rethrows -> [String] {
        let file = temp.url("Logs/nexus.log")
        NexusLog.start(file: file)
        defer { NexusLog.start(file: nil) }
        try await body()
        return NexusLog.tail(of: file, lines: 50)
    }

    func testCopyARowOpenAFolderAndPasteMakesTheCopy() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let ops = try temp.folder("Journey Ops")
        try temp.file("Journey Ops/report.pdf", "pdf")
        try temp.file("Journey Ops/notes.txt", "notes")
        try temp.folder("Journey Ops/Journey Folder")
        let tasks = queue(trashIn: try temp.folder("Trash"))
        let board = Board()
        var clipboard = FileClipboard()
        var state = try pane(at: ops)

        let log = try await withLog(temp) {
            selectRow("report.pdf", in: &state)
            let copied = ClipboardFlow.copy(ClipboardFlow.items(in: state), clipboard: &clipboard, pasteboard: board.access)
            XCTAssertTrue(copied)
            XCTAssertEqual(board.urls.map(\.lastPathComponent), ["report.pdf"], "the file is on the pasteboard for other apps")

            try openFolder("Journey Folder", in: &state)
            let pasted = ClipboardFlow.paste(into: state.location.folderURL, clipboard: &clipboard, pasteboard: board.access)
            let plan = try XCTUnwrap(pasted)
            XCTAssertEqual(board.reads, 0, "Nexus's own copy is pasted as it was copied, without reading it back")
            XCTAssertFalse(plan.moves)

            let folder = try XCTUnwrap(state.location.folderURL)
            let outcome = try await TransferFlow.run(plan.items, to: folder, moving: plan.moves, queue: tasks) { _, _ in
                XCTFail("nothing to ask about")
                return nil
            }
            let copy = folder.appendingPathComponent("report.pdf")
            XCTAssertEqual(outcome, .done([copy]))
            XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "pdf")
            XCTAssertTrue(FileManager.default.fileExists(atPath: ops.appendingPathComponent("report.pdf").path), "the original stays")
        }
        let pending = await tasks.pending
        XCTAssertTrue(pending.isEmpty, "the task ran to its end")
        XCTAssertTrue(log.contains { $0.contains("copy report.pdf") }, "\(log)")
        XCTAssertTrue(log.contains { $0.contains("paste into") && $0.contains("Journey Folder") && $0.contains("Nexus's own copy") }, "\(log)")
        XCTAssertTrue(log.contains { $0.contains("0 taken name(s)") }, "\(log)")
        XCTAssertTrue(log.contains { $0.contains("made report.pdf") }, "\(log)")
    }

    func testPasteOverATakenNameAsksOnceAndKeepBothKeepsBoth() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let ops = try temp.folder("Journey Ops")
        try temp.file("Journey Ops/notes.txt", "new")
        let existing = try temp.file("Journey Ops/Dest/notes.txt", "already here")
        let tasks = queue(trashIn: try temp.folder("Trash"))
        let board = Board()
        var clipboard = FileClipboard()
        var state = try pane(at: ops)

        selectRow("notes.txt", in: &state)
        let copied = ClipboardFlow.copy(ClipboardFlow.items(in: state), clipboard: &clipboard, pasteboard: board.access)
        XCTAssertTrue(copied)
        try openFolder("Dest", in: &state)
        let pasted = ClipboardFlow.paste(into: state.location.folderURL, clipboard: &clipboard, pasteboard: board.access)
        let plan = try XCTUnwrap(pasted)
        let folder = try XCTUnwrap(state.location.folderURL)

        var asked: [String] = []
        let outcome = try await TransferFlow.run(plan.items, to: folder, moving: plan.moves, queue: tasks) { conflict, remaining in
            asked.append(conflict.name)
            XCTAssertEqual(remaining, 0)
            return ConflictAnswer(.keepBoth)
        }
        XCTAssertEqual(asked, ["notes.txt"], "the sheet is shown once")
        let kept = folder.appendingPathComponent("notes 2.txt")
        XCTAssertEqual(outcome, .done([kept]))
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "already here")
    }

    func testCopyWithNothingSelectedLeavesThePasteboardAndThePasteSaysWhy() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let ops = try temp.folder("Journey Ops")
        try temp.file("Journey Ops/report.pdf", "pdf")
        try temp.folder("Journey Ops/Journey Folder")
        let board = Board()
        var clipboard = FileClipboard()
        var state = try pane(at: ops)

        let log = try await withLog(temp) {
            let copied = ClipboardFlow.copy(ClipboardFlow.items(in: state), clipboard: &clipboard, pasteboard: board.access)
            XCTAssertFalse(copied)
            XCTAssertEqual(board.count, 0, "nothing was written")
            try openFolder("Journey Folder", in: &state)
            let pasted = ClipboardFlow.paste(into: state.location.folderURL, clipboard: &clipboard, pasteboard: board.access)
            XCTAssertNil(pasted)
            XCTAssertEqual(board.reads, 1, "with no copy of its own, the paste reads the pasteboard")
        }
        XCTAssertTrue(log.contains { $0.contains("copy: nothing selected") }, "\(log)")
        XCTAssertTrue(log.contains { $0.contains("nothing to paste") && $0.contains("read 0 URL(s)") }, "\(log)")
    }

    func testAPaneWithNoFolderPastesNothing() throws {
        let board = Board()
        var clipboard = FileClipboard()
        clipboard.copy([URL(fileURLWithPath: "/tmp/a.txt")], changeCount: 0)
        var state = PaneState(location: .folder(URL(fileURLWithPath: "/tmp", isDirectory: true)))
        state.navigate(to: .recents)
        let pasted = ClipboardFlow.paste(into: state.location.folderURL, clipboard: &clipboard, pasteboard: board.access)
        XCTAssertNil(pasted)
    }

    func testCutThenPasteMovesAndUsesTheCutUp() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let ops = try temp.folder("Ops")
        try temp.file("Ops/a.txt")
        try temp.folder("Ops/In")
        let board = Board()
        var clipboard = FileClipboard()
        var state = try pane(at: ops)
        selectRow("a.txt", in: &state)
        let cut = ClipboardFlow.copy(ClipboardFlow.items(in: state), cut: true, clipboard: &clipboard, pasteboard: board.access)
        XCTAssertTrue(cut)
        try openFolder("In", in: &state)
        let pasted = ClipboardFlow.paste(into: state.location.folderURL, clipboard: &clipboard, pasteboard: board.access)
        let plan = try XCTUnwrap(pasted)
        XCTAssertTrue(plan.moves)
        XCTAssertEqual(clipboard, FileClipboard(), "a cut is used up by its paste")
    }

    /// Files another app put on a real pasteboard: read back as file URLs,
    /// under their own names.
    func testFilesFromAnotherAppAreReadFromTheRealPasteboard() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let notes = try temp.file("Ops/notes.txt", "theirs")
        let target = try temp.folder("Ops/Dest")
        let board = NSPasteboard(name: NSPasteboard.Name("nexus-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        SystemPasteboard.write([notes], to: board)
        XCTAssertEqual(SystemPasteboard.read(board).map(\.lastPathComponent), ["notes.txt"])

        var clipboard = FileClipboard()
        let pasted = ClipboardFlow.paste(into: target, clipboard: &clipboard, pasteboard: SystemPasteboard.access(board))
        let plan = try XCTUnwrap(pasted)
        XCTAssertEqual(plan.items.map(\.lastPathComponent), ["notes.txt"])
        let tasks = queue(trashIn: try temp.folder("Trash"))
        let outcome = try await TransferFlow.run(plan.items, to: target, moving: plan.moves, queue: tasks) { _, _ in nil }
        XCTAssertEqual(outcome, .done([target.appendingPathComponent("notes.txt")]))
    }

    func testAnEditorLeftBehindByAClosedFieldDoesNotTakeTheKeys() {
        XCTAssertTrue(TextFocus.isLive(editorInWindow: true, editorInView: true, fieldOnScreen: true), "a field being typed in")
        XCTAssertTrue(TextFocus.isLive(editorInWindow: true, editorInView: true, fieldOnScreen: nil), "a text view")
        XCTAssertFalse(TextFocus.isLive(editorInWindow: true, editorInView: false, fieldOnScreen: nil), "an editor out of every view")
        XCTAssertFalse(TextFocus.isLive(editorInWindow: true, editorInView: true, fieldOnScreen: false), "its field has gone")
        XCTAssertFalse(TextFocus.isLive(editorInWindow: false, editorInView: true, fieldOnScreen: true), "another window's")
    }

    func testTheLogKeepsItsLastLines() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let file = temp.url("Logs/grand-line/nexus.log")
        NexusLog.start(file: file)
        defer { NexusLog.start(file: nil) }
        for n in 1...30 { NexusLog.note("line \(n)\nwith a break") }
        let tail = NexusLog.tail(of: file, lines: 3)
        XCTAssertEqual(tail.count, 3)
        XCTAssertTrue(tail[2].hasSuffix(" line 30 with a break"), tail[2])
        XCTAssertEqual(NexusLog.file(home: URL(fileURLWithPath: "/Users/me")).path, "/Users/me/Library/Logs/grand-line/nexus.log")
        XCTAssertEqual(NexusLog.names([URL(fileURLWithPath: "/a/b.txt")]), "b.txt")
    }
}
