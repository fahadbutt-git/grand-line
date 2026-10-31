import XCTest
@testable import FileKit

final class RedoTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    func testRedoCopyBringsTheCopyBackFromTheTrash() async throws {
        let ops = box.operations()
        let source = try box.file("a/report.txt", "hello")
        try await ops.copy([source], to: try box.folder("b"))
        try await ops.undo()
        let redoKind = await ops.redoKind
        XCTAssertEqual(redoKind, .copy)
        let redone = try await ops.redo()
        XCTAssertEqual(redone, .copy)
        XCTAssertEqual(box.text("b/report.txt"), "hello")
        XCTAssertEqual(box.trashed, [])
        let undoKind = await ops.undoKind
        XCTAssertEqual(undoKind, .copy, "a redone operation can be undone again")
        try await ops.undo()
        XCTAssertFalse(box.exists("b/report.txt"))
        let nothing = await ops.undoKind
        XCTAssertNil(nothing)
    }

    func testRedoMoveAndRename() async throws {
        let ops = box.operations()
        let one = try box.file("a/one.txt")
        let target = try box.folder("b")
        try await ops.move([one], to: target)
        try await ops.undo()
        XCTAssertEqual(box.names("a"), ["one.txt"])
        try await ops.redo()
        XCTAssertEqual(box.names("a"), [])
        XCTAssertEqual(box.names("b"), ["one.txt"])

        try await ops.rename(box.url("b/one.txt"), to: "two.txt")
        try await ops.undo()
        XCTAssertEqual(box.names("b"), ["one.txt"])
        try await ops.redo()
        XCTAssertEqual(box.names("b"), ["two.txt"])
    }

    func testRedoTrashSendsTheItemsBack() async throws {
        let ops = box.operations()
        let one = try box.file("a/one.txt")
        try await ops.moveToTrash([one])
        try await ops.undo()
        XCTAssertEqual(box.names("a"), ["one.txt"])
        let redone = try await ops.redo()
        XCTAssertEqual(redone, .trash)
        XCTAssertEqual(box.names("a"), [])
        XCTAssertEqual(box.trashed, ["one.txt"])
    }

    func testRedoReplaceTrashesTheOldItemAgain() async throws {
        let ops = box.operations()
        let source = try box.file("a/notes.txt", "new")
        try box.file("b/notes.txt", "old")
        try await ops.copy([source], to: box.url("b"), conflict: .replace)
        try await ops.undo()
        XCTAssertEqual(box.text("b/notes.txt"), "old")
        try await ops.redo()
        XCTAssertEqual(box.text("b/notes.txt"), "new")
        XCTAssertEqual(box.names("b"), ["notes.txt"])
        XCTAssertEqual(box.trashed.count, 1, "the old item is in the Trash, never deleted")
    }

    func testANewOperationClearsRedo() async throws {
        let ops = box.operations()
        try await ops.newFolder(in: box.root)
        try await ops.undo()
        let before = await ops.redoKind
        XCTAssertEqual(before, .newFolder)
        try await ops.newFolder(in: box.root, named: "Figures")
        let after = await ops.redoKind
        XCTAssertNil(after)
        let nothing = try await ops.redo()
        XCTAssertNil(nothing)
    }
}
