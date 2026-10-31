import FileKit
import XCTest
@testable import BrowserKit

/// Cmd+C, Cmd+V into a folder, through the path Nexus's paste takes: the
/// clipboard's plan, then `TransferFlow` with the conflict questions and the
/// task engine.
final class PasteFlowTests: XCTestCase {
    private func queue(trashIn folder: URL) -> FileTaskQueue {
        FileTaskQueue(operations: FileOperations(trash: { url in
            let destination = folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }))
    }

    func testCopyThenPasteIntoAFolderMakesTheCopy() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let report = try temp.file("Ops/report.pdf", "pdf")
        let target = try temp.folder("Ops/Journey Folder")
        let tasks = queue(trashIn: try temp.folder("Trash"))

        var clipboard = FileClipboard()
        clipboard.copy([report], changeCount: 5)
        // Nexus's own copy, still on the pasteboard: no need to read it back.
        let plan = try XCTUnwrap(clipboard.plan(reading: { XCTFail("read the pasteboard"); return [] }, changeCount: 5))
        XCTAssertEqual(plan, FileClipboard.PastePlan(items: [report], moves: false))

        var asked = 0
        let outcome = try await TransferFlow.run(plan.items, to: target, moving: plan.moves, queue: tasks) { _, _ in
            asked += 1
            return nil
        }
        let copy = target.appendingPathComponent("report.pdf")
        XCTAssertEqual(outcome, .done([copy]))
        XCTAssertEqual(asked, 0, "nothing to ask about")
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.path), "the original stays")
        let pending = await tasks.pending
        XCTAssertTrue(pending.isEmpty)
    }

    func testPasteboardReferenceURLsPasteUnderTheItemsName() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let notes = try temp.file("Ops/notes.txt", "mine")
        let target = try temp.folder("Ops/Dest")
        // What the pasteboard can hand back for a file: a reference URL. Some
        // macOS versions (27 among them) give the path URL here instead, and
        // then there is nothing for this test to show.
        let reference = try XCTUnwrap((notes as NSURL).fileReferenceURL())
        if reference.lastPathComponent == notes.lastPathComponent
            || reference.standardizedFileURL.path == notes.standardizedFileURL.path {
            throw XCTSkip("this macOS gives the path URL for a file reference URL (\(reference.absoluteString))")
        }

        var clipboard = FileClipboard()
        clipboard.copy([notes], changeCount: 1)
        // Something else wrote to the pasteboard since (its count moved on).
        let plan = try XCTUnwrap(clipboard.plan(reading: { [reference, reference] }, changeCount: 2))
        XCTAssertEqual(plan.items.map(\.lastPathComponent), ["notes.txt"])

        let tasks = queue(trashIn: try temp.folder("Trash"))
        let outcome = try await TransferFlow.run(plan.items, to: target, moving: false, queue: tasks) { _, _ in nil }
        XCTAssertEqual(outcome, .done([target.appendingPathComponent("notes.txt")]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("notes.txt").path))
    }

    func testPasteOverATakenNameAsksOnceAndKeepBothKeepsBoth() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let notes = try temp.file("Ops/notes.txt", "new")
        let target = try temp.folder("Ops/Dest")
        let existing = try temp.file("Ops/Dest/notes.txt", "already here")
        let tasks = queue(trashIn: try temp.folder("Trash"))

        var questions: [(FileConflict, Int)] = []
        let outcome = try await TransferFlow.run([notes], to: target, moving: false, queue: tasks) { conflict, remaining in
            questions.append((conflict, remaining))
            return ConflictAnswer(.keepBoth)
        }
        XCTAssertEqual(questions.count, 1, "the sheet is shown once")
        XCTAssertEqual(questions.first?.0, FileConflict(source: notes, existing: existing))
        XCTAssertEqual(questions.first?.1, 0)
        XCTAssertEqual(ConflictQuestions.message(for: try XCTUnwrap(questions.first?.0)),
                       "An item named \u{201C}notes.txt\u{201D} already exists in \u{201C}Dest\u{201D}.")
        let kept = target.appendingPathComponent("notes 2.txt")
        XCTAssertEqual(outcome, .done([kept]))
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "already here", "Keep Both leaves the one already there")
    }

    func testStoppingTheQuestionsRunsNothing() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let notes = try temp.file("Ops/notes.txt", "new")
        let target = try temp.folder("Ops/Dest")
        try temp.file("Ops/Dest/notes.txt", "already here")
        let tasks = queue(trashIn: try temp.folder("Trash"))
        let outcome = try await TransferFlow.run([notes], to: target, moving: true, queue: tasks) { _, _ in nil }
        XCTAssertEqual(outcome, .stopped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path), "a stopped move leaves the item")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), ["notes.txt"])
    }
}
