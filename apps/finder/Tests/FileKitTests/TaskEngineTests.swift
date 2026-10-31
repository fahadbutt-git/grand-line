import XCTest
@testable import FileKit

/// The task engine: tasks run in order, can be cancelled waiting or running,
/// conflicts are answered per name, Rename N Items is one undo, Put Back and
/// the undo history.
final class TaskEngineTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    // MARK: Queue

    func testTasksRunInOrderAndReportTheirStates() async throws {
        let queue = FileTaskQueue(operations: box.operations())
        let first = try box.file("a/one.txt")
        let target = try box.folder("b")
        let copied = try await queue.run(.copy, title: "Copy one.txt") { try await $0.copy([first], to: target) }
        XCTAssertEqual(copied.map(\.lastPathComponent), ["one.txt"])
        let other = try box.folder("c")
        let moved = try await queue.run(.move, title: "Move one.txt") { try await $0.move([first], to: other) }
        XCTAssertEqual(moved.map(\.lastPathComponent), ["one.txt"])

        var seen: [FileTaskEvent] = []
        for await event in queue.events {
            seen.append(event)
            if seen.count == 6 { break }
        }
        XCTAssertEqual(seen.map(\.state), [.queued, .running, .finished(items: 1), .queued, .running, .finished(items: 1)])
        XCTAssertEqual(seen.map(\.id.value), [1, 1, 1, 2, 2, 2])
        XCTAssertEqual(seen.first?.kind, .copy)
        XCTAssertEqual(seen.last?.title, "Move one.txt")
        let pending = await queue.pending
        XCTAssertTrue(pending.isEmpty)
    }

    func testAWaitingTaskCanBeCancelledAndNeverRuns() async throws {
        let queue = FileTaskQueue(operations: box.operations())
        let gate = Gate()
        let blocker = await queue.enqueue(nil, title: "Hold") { _ in
            await gate.wait()
            return []
        }
        let source = try box.file("a/keep.txt")
        let target = try box.folder("b")
        let waiting = await queue.enqueue(.copy, title: "Copy keep.txt") { try await $0.copy([source], to: target) }
        await queue.cancel(waiting)
        await gate.open()
        await queue.waitUntilIdle()
        let blockerState = await queue.state(of: blocker)
        let waitingState = await queue.state(of: waiting)
        XCTAssertEqual(blockerState, .finished(items: 0))
        XCTAssertEqual(waitingState, .cancelled)
        XCTAssertFalse(box.exists("b/keep.txt"), "a cancelled task never starts")
    }

    func testACancelledCopyStopsAndLeavesNoHalfItem() async throws {
        let ops = box.operations()
        try box.file("big/one.txt")
        try box.file("big/two.txt")
        let target = try box.folder("out")
        let source = box.url("big")
        let task = Task { () async throws -> [URL] in
            while !Task.isCancelled { await Task.yield() }
            return try await ops.copy([source], to: target)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled copy finished")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(box.names("out"), [], "nothing half copied is left")
        let kind = await ops.undoKind
        XCTAssertNil(kind, "a copy that did nothing leaves nothing to undo")
    }

    func testAFailedTaskSaysWhy() async throws {
        let queue = FileTaskQueue(operations: box.operations())
        let ghost = box.url("ghost.txt")
        let root = box.root
        do {
            try await queue.run(.copy, title: "Copy ghost.txt") { try await $0.copy([ghost], to: root) }
            XCTFail("copied a missing file")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .missing(ghost))
        }
        var last: FileTaskEvent?
        for await event in queue.events {
            last = event
            if event.state.isDone { break }
        }
        XCTAssertEqual(last?.state, .failed("ghost.txt is no longer there."))
    }

    // MARK: Conflicts

    func testConflictsAreFoundBeforeTheTaskStarts() throws {
        let a = try box.file("a/report.pdf")
        let b = try box.file("a/notes.txt")
        try box.file("b/report.pdf")
        let found = FileOperations.conflicts([a, b], in: box.url("b"))
        XCTAssertEqual(found.map(\.name), ["report.pdf"])
        XCTAssertEqual(found.first?.existing.lastPathComponent, "report.pdf")
        XCTAssertTrue(FileOperations.conflicts([a], in: box.url("a")).isEmpty, "the items' own folder is no conflict")
    }

    func testEachConflictTakesItsOwnAnswer() async throws {
        let ops = box.operations()
        let first = try box.file("a/one.txt", "new one")
        let second = try box.file("a/two.txt", "new two")
        let third = try box.file("a/three.txt", "new three")
        try box.file("b/one.txt", "old one")
        try box.file("b/two.txt", "old two")
        try box.file("b/three.txt", "old three")
        let resolution = ConflictResolution(.skip, byName: ["one.txt": .replace, "two.txt": .keepBoth])
        let made = try await ops.copy([first, second, third], to: box.url("b"), resolution: resolution)
        XCTAssertEqual(made.map(\.lastPathComponent), ["one.txt", "two 2.txt"])
        XCTAssertEqual(box.text("b/one.txt"), "new one")
        XCTAssertEqual(box.text("b/two.txt"), "old two")
        XCTAssertEqual(box.text("b/three.txt"), "old three")
        XCTAssertEqual(box.trashed, ["one.txt"], "the replaced item went to the Trash")
        try await ops.undo()
        XCTAssertEqual(box.text("b/one.txt"), "old one", "undo brings the replaced item back")
        XCTAssertFalse(box.exists("b/two 2.txt"))
    }

    // MARK: Rename N Items

    func testRenameItemsIsOneUndoAndSwapsNames() async throws {
        let ops = box.operations()
        let a = try box.file("p/a.txt", "A")
        let b = try box.file("p/b.txt", "B")
        let c = try box.file("p/c.txt", "C")
        let renamed = try await ops.renameItems([(item: a, name: "b.txt"), (item: b, name: "a.txt"), (item: c, name: "Chapter 3.txt")])
        XCTAssertEqual(renamed.map(\.lastPathComponent), ["b.txt", "a.txt", "Chapter 3.txt"])
        XCTAssertEqual(box.text("p/b.txt"), "A")
        XCTAssertEqual(box.text("p/a.txt"), "B")
        XCTAssertEqual(box.text("p/Chapter 3.txt"), "C")
        let kind = await ops.undoKind
        XCTAssertEqual(kind, .renameItems)
        try await ops.undo()
        XCTAssertEqual(box.names("p"), ["a.txt", "b.txt", "c.txt"])
        XCTAssertEqual(box.text("p/a.txt"), "A")
        try await ops.redo()
        XCTAssertEqual(box.names("p"), ["Chapter 3.txt", "a.txt", "b.txt"])
        XCTAssertEqual(box.text("p/a.txt"), "B")
    }

    func testRenameItemsRefusesClashesAndChangesNothing() async throws {
        let ops = box.operations()
        let a = try box.file("p/a.txt")
        let b = try box.file("p/b.txt")
        try box.file("p/other.txt")
        do {
            try await ops.renameItems([(item: a, name: "same.txt"), (item: b, name: "SAME.txt")])
            XCTFail("two items took one name")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .duplicateNames(["SAME.txt"]))
        }
        do {
            try await ops.renameItems([(item: a, name: "x.txt"), (item: b, name: "other.txt")])
            XCTFail("renamed over an item outside the batch")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .nameTaken("other.txt"))
        }
        do {
            try await ops.renameItems([(item: a, name: "bad/name")])
            XCTFail("accepted a slash")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .invalidName("bad/name"))
        }
        XCTAssertEqual(box.names("p"), ["a.txt", "b.txt", "other.txt"])
        let kind = await ops.undoKind
        XCTAssertNil(kind)
    }

    // MARK: Put Back, created items, history

    func testPutBackIsOneStepAndKeepsBothWhenTheNameIsTaken() async throws {
        let ops = box.operations()
        let report = try box.file("docs/report.pdf", "first")
        let trashed = try await ops.moveToTrash([report])
        try box.file("docs/report.pdf", "new")
        let back = try await ops.putBack([(item: trashed[0], original: report)])
        XCTAssertEqual(back.map(\.lastPathComponent), ["report 2.pdf"])
        XCTAssertEqual(box.text("docs/report 2.pdf"), "first")
        let kind = await ops.undoKind
        XCTAssertEqual(kind, .putBack)
        try await ops.undo()
        XCTAssertFalse(box.exists("docs/report 2.pdf"))
        XCTAssertEqual(box.trashed, ["report.pdf"])
    }

    func testItemsMadeElsewhereUndoToTheTrash() async throws {
        let ops = box.operations()
        let archive = try box.file("a/Archive.zip")
        await ops.recordCreated([archive], kind: .compress)
        let kind = await ops.undoKind
        XCTAssertEqual(kind, .compress)
        try await ops.undo()
        XCTAssertFalse(box.exists("a/Archive.zip"))
        XCTAssertEqual(box.trashed, ["Archive.zip"], "never deleted, only moved to the Trash")
    }

    func testHistoryListsNewestFirstAndUndoesSeveralSteps() async throws {
        let ops = box.operations()
        let folder = try await ops.newFolder(in: box.root)
        let notes = try box.file("notes.txt")
        try await ops.duplicate([notes])
        try await ops.moveToTrash([notes])
        let history = await ops.history
        XCTAssertEqual(history.map(\.kind), [.trash, .duplicate, .newFolder])
        XCTAssertEqual(history.first?.names, ["notes.txt"])
        XCTAssertEqual(history.last?.names, [folder.lastPathComponent])
        let undone = try await ops.undo(steps: 2)
        XCTAssertEqual(undone, [.trash, .duplicate])
        XCTAssertTrue(box.exists("notes.txt"))
        XCTAssertFalse(box.exists("notes copy.txt"))
        let left = await ops.history
        XCTAssertEqual(left.map(\.kind), [.newFolder])
    }
}

/// Holds a task until opened.
actor Gate {
    private var isOpen = false

    func wait() async {
        while !isOpen { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    func open() {
        isOpen = true
    }
}
