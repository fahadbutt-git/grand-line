import XCTest
@testable import FileKit

final class FileOperationsTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    func testCopyAndUndo() async throws {
        let ops = box.operations()
        let source = try box.file("a/report.txt", "hello")
        let target = try box.folder("b")
        let copies = try await ops.copy([source], to: target)
        XCTAssertEqual(copies.map(\.path), [box.url("b/report.txt").path])
        XCTAssertEqual(box.text("b/report.txt"), "hello")
        XCTAssertTrue(box.exists("a/report.txt"))
        let kind = await ops.undoKind
        XCTAssertEqual(kind, .copy)
        let undone = try await ops.undo()
        XCTAssertEqual(undone, .copy)
        XCTAssertFalse(box.exists("b/report.txt"))
        XCTAssertEqual(box.trashed, ["report.txt"])
        let nothing = try await ops.undo()
        XCTAssertNil(nothing)
    }

    func testCopyFolderKeepsContentsAndTags() async throws {
        let ops = box.operations()
        try box.file("a/Project/one.txt")
        try box.file("a/Project/inner/two.txt")
        try (box.url("a/Project") as NSURL).setResourceValue(["Blue"], forKey: .tagNamesKey)
        let copies = try await ops.copy([box.url("a/Project")], to: try box.folder("b"))
        XCTAssertEqual(copies.count, 1)
        XCTAssertTrue(box.exists("b/Project/one.txt"))
        XCTAssertTrue(box.exists("b/Project/inner/two.txt"))
        let tags = try box.url("b/Project").resourceValues(forKeys: [.tagNamesKey]).tagNames
        XCTAssertEqual(tags, ["Blue"])
    }

    func testKeepBothReplaceAndSkip() async throws {
        let ops = box.operations()
        let source = try box.file("a/notes.txt", "new")
        try box.file("b/notes.txt", "old")
        let target = box.url("b")

        let kept = try await ops.copy([source], to: target, conflict: .keepBoth)
        XCTAssertEqual(kept.map(\.lastPathComponent), ["notes 2.txt"])
        let again = try await ops.copy([source], to: target, conflict: .keepBoth)
        XCTAssertEqual(again.map(\.lastPathComponent), ["notes 3.txt"])

        let skipped = try await ops.copy([source], to: target, conflict: .skip)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertEqual(box.text("b/notes.txt"), "old")

        try await ops.copy([source], to: target, conflict: .replace)
        XCTAssertEqual(box.text("b/notes.txt"), "new")
        XCTAssertEqual(box.trashed, ["notes.txt"])
        try await ops.undo()
        XCTAssertEqual(box.text("b/notes.txt"), "old")
        XCTAssertTrue(box.trashed.count == 1)
    }

    func testCopyIntoSameFolderKeepsBoth() async throws {
        let ops = box.operations()
        let source = try box.file("a/plan.md")
        let copies = try await ops.copy([source], to: box.url("a"), conflict: .replace)
        XCTAssertEqual(copies.map(\.lastPathComponent), ["plan 2.md"])
    }

    func testTwoItemsWithOneName() async throws {
        let ops = box.operations()
        let first = try box.file("a/x.txt", "1")
        let second = try box.file("b/x.txt", "2")
        let copies = try await ops.copy([first, second], to: try box.folder("c"))
        XCTAssertEqual(copies.map(\.lastPathComponent), ["x.txt", "x 2.txt"])
    }

    func testNoCopyIntoItself() async throws {
        let ops = box.operations()
        let folder = try box.folder("a")
        try box.folder("a/inner")
        do {
            try await ops.copy([folder], to: box.url("a/inner"))
            XCTFail("copied into itself")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .intoItself(folder))
        }
    }

    func testReplaceNeverTrashesASource() async throws {
        let ops = box.operations()
        let inner = try box.file("x/y/x/file.txt")
        do {
            try await ops.move([inner.deletingLastPathComponent()], to: box.url("x/y"), conflict: .replace)
        } catch {
            XCTFail("moving into the same folder is a no-op: \(error)")
        }
        do {
            try await ops.move([box.url("x/y/x")], to: box.root, conflict: .replace)
            XCTFail("trashed its own source")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .replacesSource(box.root.appendingPathComponent("x")))
        }
    }

    func testMoveAndUndo() async throws {
        let ops = box.operations()
        let source = try box.file("a/move me.txt")
        let moved = try await ops.move([source], to: try box.folder("b"))
        XCTAssertEqual(moved.map(\.path), [box.url("b/move me.txt").path])
        XCTAssertFalse(box.exists("a/move me.txt"))
        try await ops.undo()
        XCTAssertTrue(box.exists("a/move me.txt"))
        XCTAssertFalse(box.exists("b/move me.txt"))
    }

    func testCutAndPaste() async throws {
        let ops = box.operations()
        let source = try box.file("a/cut.txt")
        await ops.cut([source])
        let pending = await ops.cutPending
        XCTAssertEqual(pending, [source])
        let pasted = try await ops.pasteCut(into: try box.folder("b"))
        XCTAssertEqual(pasted.map(\.lastPathComponent), ["cut.txt"])
        let after = await ops.cutPending
        XCTAssertTrue(after.isEmpty)
        await ops.cut([box.url("b/cut.txt")])
        await ops.cancelCut()
        let cancelled = await ops.cutPending
        XCTAssertTrue(cancelled.isEmpty)
        let undoBefore = await ops.undoKind
        let none = try await ops.pasteCut(into: box.url("a"))
        XCTAssertTrue(none.isEmpty)
        let undoAfter = await ops.undoKind
        XCTAssertEqual(undoAfter, undoBefore, "an empty paste adds nothing to undo")
    }

    func testDuplicate() async throws {
        let ops = box.operations()
        let source = try box.file("a/Report.pdf")
        let first = try await ops.duplicate([source])
        let second = try await ops.duplicate([source])
        XCTAssertEqual(first.map(\.lastPathComponent), ["Report copy.pdf"])
        XCTAssertEqual(second.map(\.lastPathComponent), ["Report copy 2.pdf"])
        try await ops.undo()
        XCTAssertFalse(box.exists("a/Report copy 2.pdf"))
        XCTAssertTrue(box.exists("a/Report copy.pdf"))
    }

    func testRename() async throws {
        let ops = box.operations()
        let source = try box.file("a/draft.txt")
        try box.file("a/taken.txt")
        let renamed = try await ops.rename(source, to: "final.txt")
        XCTAssertEqual(renamed.lastPathComponent, "final.txt")
        do {
            try await ops.rename(renamed, to: "taken.txt")
            XCTFail("renamed over another file")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .nameTaken("taken.txt"))
        }
        do {
            try await ops.rename(renamed, to: "bad/name")
            XCTFail("accepted a slash")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .invalidName("bad/name"))
        }
        let cased = try await ops.rename(renamed, to: "Final.txt")
        XCTAssertEqual(box.names("a"), ["Final.txt", "taken.txt"])
        try await ops.undo()
        XCTAssertEqual(box.names("a"), ["final.txt", "taken.txt"])
        try await ops.undo()
        XCTAssertEqual(box.names("a"), ["draft.txt", "taken.txt"])
        XCTAssertEqual(cased.lastPathComponent, "Final.txt")
    }

    func testNewFolder() async throws {
        let ops = box.operations()
        let parent = try box.folder("a")
        let first = try await ops.newFolder(in: parent)
        let second = try await ops.newFolder(in: parent)
        XCTAssertEqual([first, second].map(\.lastPathComponent), ["untitled folder", "untitled folder 2"])
        let named = try await ops.newFolder(in: parent, named: "Figures")
        XCTAssertEqual(named.lastPathComponent, "Figures")
        try await ops.undo()
        XCTAssertFalse(box.exists("a/Figures"))
        XCTAssertEqual(box.trashed, ["Figures"])
    }

    func testMoveToTrashAndUndo() async throws {
        let ops = box.operations()
        let one = try box.file("a/one.txt")
        let two = try box.file("a/two.txt")
        let places = try await ops.moveToTrash([one, two])
        XCTAssertEqual(places.map(\.lastPathComponent), ["one.txt", "two.txt"])
        XCTAssertEqual(box.names("a"), [])
        let kind = try await ops.undo()
        XCTAssertEqual(kind, .trash)
        XCTAssertEqual(box.names("a"), ["one.txt", "two.txt"])
        XCTAssertEqual(box.trashed, [])
    }

    func testUndoTrashKeepsANewItemInTheWay() async throws {
        let ops = box.operations()
        let one = try box.file("a/one.txt", "first")
        try await ops.moveToTrash([one])
        try box.file("a/one.txt", "second")
        try await ops.undo()
        XCTAssertEqual(box.names("a"), ["one 2.txt", "one.txt"])
        XCTAssertEqual(box.text("a/one 2.txt"), "first")
    }

    func testProgressReachesTheEnd() async throws {
        let ops = box.operations()
        for i in 0..<5 { try box.file("src/f\(i).txt", String(repeating: "x", count: 100)) }
        try await ops.copy([box.url("src")], to: try box.folder("dst"))
        var last: OperationProgress?
        for await update in ops.progress {
            last = update
            if update.isFinished { break }
        }
        XCTAssertEqual(last?.kind, .copy)
        XCTAssertEqual(last?.totalFiles, 5)
        XCTAssertEqual(last?.completedBytes, 500)
        XCTAssertEqual(last?.fraction, 1)
    }

    func testMissingSource() async throws {
        let ops = box.operations()
        let ghost = box.url("nothing.txt")
        do {
            try await ops.copy([ghost], to: box.root)
            XCTFail("copied a missing file")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .missing(ghost))
        }
    }

    func testThousandFileCopyAndUndo() async throws {
        let ops = box.operations()
        for i in 0..<1_000 { try box.file("big/sub\(i % 10)/file \(i).txt", "\(i)") }
        let start = Date()
        try await ops.copy([box.url("big")], to: try box.folder("out"))
        print("copied 1,000 files in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        let copied = FileManager.default.enumerator(atPath: box.url("out/big").path)?.allObjects.count
        XCTAssertEqual(copied, 1_010)
        XCTAssertEqual(box.text("out/big/sub7/file 517.txt"), "517")
        try await ops.undo()
        XCTAssertFalse(box.exists("out/big"))
        XCTAssertEqual(box.trashed, ["big"])
        XCTAssertTrue(box.exists("big/sub7/file 517.txt"))
    }
}
