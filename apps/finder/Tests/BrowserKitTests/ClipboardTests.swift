import FileKit
import XCTest
@testable import BrowserKit

/// R8: real cut and paste, and the transfer list.
final class ClipboardTests: XCTestCase {
    let a = URL(fileURLWithPath: "/Users/me/Downloads/a.pdf")
    let b = URL(fileURLWithPath: "/Users/me/Downloads/b.pdf")

    func testCutThenPasteMoves() {
        var clipboard = FileClipboard()
        clipboard.cut([a, b], changeCount: 7)
        XCTAssertTrue(clipboard.isCut(a))
        XCTAssertEqual(clipboard.cutPaths, [a.path, b.path])
        let plan = clipboard.plan(pasteboard: [a, b], changeCount: 7)
        XCTAssertEqual(plan, FileClipboard.PastePlan(items: [a, b], moves: true))
        clipboard.didPaste(plan!)
        XCTAssertFalse(clipboard.isCut(a), "a cut is used up by its paste")
    }

    func testSomethingNewOnThePasteboardCancelsTheCut() {
        var clipboard = FileClipboard()
        clipboard.cut([a], changeCount: 7)
        let plan = clipboard.plan(pasteboard: [b], changeCount: 8)
        XCTAssertEqual(plan, FileClipboard.PastePlan(items: [b], moves: false))
    }

    func testCopyPastesAgainAndOptionMoves() {
        var clipboard = FileClipboard()
        clipboard.copy([a])
        let plan = clipboard.plan(pasteboard: [a], changeCount: 3)!
        XCTAssertFalse(plan.moves)
        clipboard.didPaste(plan)
        XCTAssertNotNil(clipboard.plan(pasteboard: [a], changeCount: 3))
        XCTAssertEqual(clipboard.plan(pasteboard: [a], changeCount: 3, forceMove: true)?.moves, true)
        XCTAssertNil(clipboard.plan(pasteboard: [], changeCount: 3))
    }

    func testTransferList() {
        var list = TransferList()
        list.apply(OperationProgress(kind: .copy, completedFiles: 12, totalFiles: 40, completedBytes: 10, totalBytes: 100, current: a))
        XCTAssertTrue(list.isBusy)
        XCTAssertEqual(list.summary, "Copying 12 of 40")
        list.apply(OperationProgress(kind: .copy, completedFiles: 40, totalFiles: 40, completedBytes: 100, totalBytes: 100, current: nil))
        XCTAssertFalse(list.isBusy)
        XCTAssertEqual(list.done.first?.files, 40)
        for _ in 0..<30 {
            list.apply(OperationProgress(kind: .trash, completedFiles: 1, totalFiles: 1, completedBytes: 0, totalBytes: 0, current: nil))
        }
        XCTAssertEqual(list.done.count, TransferList.keep)
    }

    func testCutAndPasteWithFileKitMovesAndUndoes() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let file = try temp.file("Downloads/report.pdf")
        let target = try temp.folder("Documents")
        let trash = try temp.folder("Trash")
        let operations = FileOperations(trash: { url in
            let destination = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        var clipboard = FileClipboard()
        clipboard.cut([file], changeCount: 1)
        let plan = try XCTUnwrap(clipboard.plan(pasteboard: [file], changeCount: 1))
        XCTAssertTrue(plan.moves)
        _ = try await operations.move(plan.items, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("report.pdf").path))
        _ = try await operations.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
