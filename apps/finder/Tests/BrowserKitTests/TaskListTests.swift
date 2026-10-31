import FileKit
import XCTest
@testable import BrowserKit

/// The tasks popover and the conflict sheet.
final class TaskListTests: XCTestCase {
    let a = URL(fileURLWithPath: "/Users/me/Downloads/a.pdf")

    func testTasksFollowTheEngineAndTakeTheProgress() {
        var list = TransferList()
        list.apply(FileTaskEvent(id: FileTaskID(1), kind: .copy, title: "Copy 3 items", state: .queued))
        list.apply(FileTaskEvent(id: FileTaskID(2), kind: .trash, title: "Move 1 item to the Trash", state: .queued))
        XCTAssertEqual(list.active.map(\.id.value), [1, 2], "oldest first")
        XCTAssertEqual(list.summary, "2 tasks")
        XCTAssertTrue(list.isBusy)
        XCTAssertEqual(list.active.first?.status, "Waiting")

        list.apply(FileTaskEvent(id: FileTaskID(1), kind: .copy, title: "Copy 3 items", state: .running))
        list.apply(OperationProgress(kind: .copy, completedFiles: 1, totalFiles: 3, completedBytes: 10, totalBytes: 30, current: a))
        XCTAssertEqual(list.active.first?.status, "Copying 1 of 3")
        XCTAssertEqual(list.active.first?.fraction ?? 0, 1.0 / 3, accuracy: 0.001)
        XCTAssertNil(list.active.last?.fraction, "a waiting task shows no bar")

        list.markCancelling(FileTaskID(2))
        XCTAssertEqual(list.active.last?.status, "Stopping")
        list.apply(OperationProgress(kind: .copy, completedFiles: 3, totalFiles: 3, completedBytes: 30, totalBytes: 30, current: nil))
        list.apply(FileTaskEvent(id: FileTaskID(1), kind: .copy, title: "Copy 3 items", state: .finished(items: 3)))
        list.apply(FileTaskEvent(id: FileTaskID(2), kind: .trash, title: "Move 1 item to the Trash", state: .cancelled))
        XCTAssertTrue(list.active.isEmpty)
        XCTAssertFalse(list.isBusy)
        XCTAssertEqual(list.ended.map(\.status), ["Stopped", "Done, 3 items"])
        XCTAssertEqual(list.done.first?.files, 3, "the finished operation is still listed")
        list.clearEnded()
        XCTAssertTrue(list.tasks.isEmpty)
    }

    func testEndedTasksAreKeptToALimit() {
        var list = TransferList()
        for n in 1...30 {
            list.apply(FileTaskEvent(id: FileTaskID(n), kind: .duplicate, title: "Duplicate", state: .queued))
            list.apply(FileTaskEvent(id: FileTaskID(n), kind: .duplicate, title: "Duplicate", state: .failed("No room")))
        }
        XCTAssertEqual(list.tasks.count, TransferList.keep)
        XCTAssertEqual(list.tasks.first?.id.value, 30, "newest first")
        XCTAssertEqual(list.tasks.first?.status, "No room")
    }

    func testTaskTitlesSayWhatAndWhere() {
        let docs = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
        XCTAssertEqual(TaskTitles.title(.copy, [a], to: docs), "Copy a.pdf to Documents")
        XCTAssertEqual(TaskTitles.title(.move, [a, a, a], to: docs), "Move 3 items to Documents")
        XCTAssertEqual(TaskTitles.title(.trash, [a]), "Move a.pdf to the Trash")
        XCTAssertEqual(TaskTitles.title(.copy, [a], to: URL(fileURLWithPath: "/Users/me/.Trash")), "Copy a.pdf to the Trash")
        XCTAssertEqual(TaskTitles.title(.extract, [a, a], to: docs), "Extract 2 items to Documents")
        let now = Date()
        XCTAssertEqual(TaskTitles.history(OperationRecord(kind: .copy, count: 1, names: ["a.pdf"], date: now)), "Copy: a.pdf")
        XCTAssertEqual(TaskTitles.history(OperationRecord(kind: .trash, count: 3, names: ["a", "b", "c"], date: now)), "Move to Trash: 3 items")
    }

    // MARK: Conflicts

    func testOneAnswerPerNameUntilApplyToAll() async {
        let folder = URL(fileURLWithPath: "/Users/me/Documents")
        let conflicts = ["a.txt", "b.txt", "c.txt", "d.txt"].map {
            FileConflict(source: URL(fileURLWithPath: "/Users/me/Downloads/" + $0), existing: folder.appendingPathComponent($0))
        }
        var asked: [(String, Int)] = []
        let resolution = await ConflictQuestions.resolve(conflicts) { conflict, remaining in
            asked.append((conflict.name, remaining))
            switch conflict.name {
            case "a.txt": return ConflictAnswer(.replace)
            case "b.txt": return ConflictAnswer(.skip, applyToAll: true)
            default: return ConflictAnswer(.keepBoth)
            }
        }
        XCTAssertEqual(asked.map { $0.0 }, ["a.txt", "b.txt"], "Apply to All ends the questions")
        XCTAssertEqual(asked.map { $0.1 }, [3, 2])
        XCTAssertEqual(resolution?.policy(for: "a.txt"), .replace)
        XCTAssertEqual(resolution?.policy(for: "c.txt"), .skip)
        XCTAssertEqual(resolution?.policy(for: "d.txt"), .skip)
    }

    func testStopEndsTheTaskBeforeItStarts() async {
        let conflict = FileConflict(source: a, existing: URL(fileURLWithPath: "/Users/me/Documents/a.pdf"))
        let resolution = await ConflictQuestions.resolve([conflict]) { _, _ in nil }
        XCTAssertNil(resolution)
        let none = await ConflictQuestions.resolve([]) { _, _ in nil }
        XCTAssertEqual(none, ConflictResolution(.keepBoth), "no conflicts, nothing asked")
    }

    func testTheQuestionNamesTheItemAndTheFolder() {
        let conflict = FileConflict(source: a, existing: URL(fileURLWithPath: "/Users/me/Documents/a.pdf"))
        XCTAssertEqual(ConflictQuestions.message(for: conflict), "An item named \u{201C}a.pdf\u{201D} already exists in \u{201C}Documents\u{201D}.")
        XCTAssertTrue(ConflictQuestions.detail(for: conflict, remaining: 2).hasSuffix("2 more items have the same problem."))
        XCTAssertTrue(ConflictQuestions.detail(for: conflict, remaining: 0).contains("Trash"))
    }
}
