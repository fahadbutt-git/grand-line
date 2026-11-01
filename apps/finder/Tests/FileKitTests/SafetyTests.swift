import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import FileKit

/// The data-safety promises, each on a temporary folder with a pretend Trash:
/// nothing is lost or deleted outright, a link is the folder it points to, a
/// folder never goes into itself, metadata travels with a copy, and Undo,
/// Redo and Put Back never forget half of what they did.
final class SafetyTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    private func link(_ relative: String, to target: URL) throws -> URL {
        let url = box.url(relative)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        return url
    }

    private func hidden(_ relative: String = "") -> [String] {
        box.names(relative).filter { $0.hasPrefix(".rename-") }
    }

    // MARK: Paths compared by what they reach (N3)

    func testAFolderThroughALinkIsTheSameFolder() async throws {
        let real = try box.folder("Cloud/X")
        try box.file("Cloud/X/report.pdf", "mine")
        let linked = try link("Drive", to: box.url("Cloud"))
        let viaLink = linked.appendingPathComponent("X/report.pdf")
        XCTAssertTrue(FileIdentity.sameFolder(linked.appendingPathComponent("X"), real))
        XCTAssertTrue(FileIdentity.sameItem(viaLink, box.url("Cloud/X/report.pdf")))

        // No conflict sheet for the file itself.
        XCTAssertEqual(FileOperations.conflicts([viaLink], in: real), [])

        // Replace never sends the source to the Trash: copying keeps both, moving leaves it.
        let ops = box.operations()
        let copies = try await ops.copy([viaLink], to: real, conflict: .replace)
        XCTAssertEqual(copies.map(\.lastPathComponent), ["report 2.pdf"])
        XCTAssertEqual(box.text("Cloud/X/report.pdf"), "mine")
        let moved = try await ops.move([viaLink], to: real, conflict: .replace)
        XCTAssertEqual(moved, [])
        XCTAssertEqual(box.text("Cloud/X/report.pdf"), "mine")
        XCTAssertEqual(box.trashed, [])
    }

    func testAFolderIsNeverCopiedIntoItselfThroughALink() async throws {
        try box.file("F/sub/a.txt")
        let linked = try link("L", to: box.url("F"))
        let ops = box.operations()
        do {
            try await ops.copy([box.url("F")], to: linked.appendingPathComponent("sub"))
            XCTFail("a folder went into itself")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .intoItself(box.url("F")))
        }
        do {
            try await ops.move([box.url("F")], to: linked.appendingPathComponent("sub"))
            XCTFail("a folder moved into itself")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .intoItself(box.url("F")))
        }
        XCTAssertEqual(box.names("F/sub"), ["a.txt"])
        // A link itself is copied as a link, which is safe.
        let copied = try await ops.copy([linked], to: box.url("F/sub"))
        XCTAssertEqual(copied.map(\.lastPathComponent), ["L"])
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: box.url("F/sub/L").path))
    }

    func testTheTreeCopyStopsAtTheCopyBeingMade() throws {
        try box.file("F/a.txt")
        // The destination is inside the source: the copy must not walk into it.
        XCTAssertThrowsError(try FileTree.copy(box.url("F"), to: box.url("F/F copy")) { _, _ in }) { error in
            guard case .intoItself(let url)? = error as? FileOperationError else { return XCTFail("\(error)") }
            XCTAssertEqual(url.lastPathComponent, "F copy")
        }
    }

    // MARK: Names compared without case, partial copies (N10)

    func testNamesDifferingOnlyInCaseKeepBoth() async throws {
        try box.file("a/Notes/one.txt", "1")
        try box.file("b/notes/two.txt", "2")
        let ops = box.operations()
        let copies = try await ops.copy([box.url("a/Notes"), box.url("b/notes")], to: try box.folder("c"))
        XCTAssertEqual(copies.map(\.lastPathComponent), ["Notes", "notes 2"])
        XCTAssertEqual(box.trashed, [], "nothing that was just copied went to the Trash")
        XCTAssertEqual(box.text("c/Notes/one.txt"), "1")
        XCTAssertEqual(box.text("c/notes 2/two.txt"), "2")
        XCTAssertEqual(FileNaming.keepBoth("notes", in: box.url("c"), avoiding: ["NOTES 2"]), "notes 3")
    }

    func testANameTakenAfterPlanningIsKeptNotOverwritten() async throws {
        let source = try box.file("a/report.txt", "new")
        try box.folder("b")
        let ops = box.operations()
        let steps = try await ops.plan([source], into: box.url("b"), conflict: .keepBoth, moving: false)
        XCTAssertEqual(steps.map(\.destination.lastPathComponent), ["report.txt"])
        // Something else arrives under that name before the copy runs.
        try box.file("b/report.txt", "theirs")
        let copies = try await ops.copy([source], to: box.url("b"))
        XCTAssertEqual(copies.map(\.lastPathComponent), ["report 2.txt"])
        XCTAssertEqual(box.text("b/report.txt"), "theirs")
    }

    func testAStoppedCopyTrashesOnlyItsOwnHalfCopy() async throws {
        for i in 0..<20 { try box.file("a/Big/\(i).txt", String(repeating: "x", count: 10)) }
        try box.folder("b")
        let ops = box.operations()
        let source = box.url("a/Big")
        let target = box.url("b")
        let task = Task { try await ops.copy([source], to: target) }
        task.cancel()
        _ = try? await task.value
        XCTAssertEqual(box.names("b"), [], "a half copy does not stay")
        XCTAssertTrue(box.trashed.allSatisfy { $0.hasPrefix("Big") })
        XCTAssertEqual(box.names("a/Big").count, 20, "the source is untouched")
    }

    // MARK: Folder metadata (N6)

    func testAFolderCopyKeepsItsExtendedAttributesAndQuarantine() async throws {
        try box.file("a/MyApp.app/Contents/Info.plist", "<plist/>")
        let flag = Data("0081;65f00000;Safari;".utf8)
        let custom = Data("blue".utf8)
        for (url, name, value) in [(box.url("a/MyApp.app"), "com.apple.quarantine", flag),
                                   (box.url("a/MyApp.app"), "org.example.note", custom),
                                   (box.url("a/MyApp.app/Contents/Info.plist"), "com.apple.quarantine", flag)] {
            XCTAssertTrue(setAttribute(name, value, on: url), name)
        }
        let ops = box.operations()
        try await ops.copy([box.url("a/MyApp.app")], to: try box.folder("b"))
        XCTAssertEqual(attribute("com.apple.quarantine", of: box.url("b/MyApp.app")), flag, "the bundle keeps its quarantine flag")
        XCTAssertEqual(attribute("org.example.note", of: box.url("b/MyApp.app")), custom)
        XCTAssertEqual(attribute("com.apple.quarantine", of: box.url("b/MyApp.app/Contents/Info.plist")), flag)
    }

    private func setAttribute(_ name: String, _ value: Data, on url: URL) -> Bool {
        value.withUnsafeBytes { buffer in
            setxattr(url.path, name, buffer.baseAddress, value.count, 0, XATTR_NOFOLLOW) == 0
        }
    }

    private func attribute(_ name: String, of url: URL) -> Data? {
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read > 0 ? data.prefix(read) : nil
    }

    // MARK: Renames (N5)

    func testUndoOfARenameNeverGoesOverANewItem() async throws {
        let ops = box.operations()
        let a = try box.file("a.txt", "first")
        try await ops.rename(a, to: "b.txt")
        try box.file("a.txt", "second")
        do {
            try await ops.undo()
            XCTFail("undo put one item over another")
        } catch {
            XCTAssertEqual(error as? FileOperationError, .nameTaken("a.txt"))
        }
        XCTAssertEqual(box.text("a.txt"), "second")
        XCTAssertEqual(box.text("b.txt"), "first")
        XCTAssertEqual(hidden(), [], "nothing is left under a hidden name")
        let kind = await ops.undoKind
        XCTAssertEqual(kind, .rename, "the rename can still be undone once the name is free")
    }

    func testACaseOnlyRenameAndItsUndo() async throws {
        let ops = box.operations()
        try await ops.rename(try box.file("a.txt", "x"), to: "A.txt")
        XCTAssertEqual(box.names(), ["A.txt"])
        try await ops.undo()
        XCTAssertEqual(box.names(), ["a.txt"])
        XCTAssertEqual(hidden(), [])
    }

    func testACaseOnlyRenameThatFailsGoesBack() throws {
        let a = try box.file("a.txt", "x")
        // The second step cannot land: the item must not stay under the hidden name.
        XCTAssertThrowsError(try FileOperations.renameCaseOnly(a, to: box.url("missing/A.txt")))
        XCTAssertEqual(box.text("a.txt"), "x")
        XCTAssertEqual(hidden(), [])
        // A different item under the new name is refused before anything moves.
        try box.file("b.txt", "y")
        XCTAssertThrowsError(try FileOperations.renameCaseOnly(a, to: box.url("b.txt"))) { error in
            XCTAssertEqual(error as? FileOperationError, .nameTaken("b.txt"))
        }
        XCTAssertEqual(box.text("b.txt"), "y")
    }

    func testRenameManyRefusesANameTakenSince() async throws {
        let ops = box.operations()
        try await ops.renameItems([(item: try box.file("a.txt", "a"), name: "c.txt"), (item: try box.file("b.txt", "b"), name: "d.txt")])
        try box.file("a.txt", "new")
        do {
            try await ops.undo()
            XCTFail("undo went over a new item")
        } catch {}
        XCTAssertEqual(box.names(), ["a.txt", "c.txt", "d.txt"])
        XCTAssertEqual(box.text("a.txt"), "new")
        XCTAssertEqual(hidden(), [])
    }

    // MARK: Undo that stops partway (N9)

    func testAnUndoThatStopsPartwayKeepsBothHalves() async throws {
        let ops = box.operations()
        let files = try ["a.txt", "b.txt", "c.txt"].map { try box.file("A/" + $0, $0) }
        try await ops.move(files, to: try box.folder("B"))
        // a.txt is undone last; it is renamed away, so its step fails.
        try FileManager.default.moveItem(at: box.url("B/a.txt"), to: box.url("B/x.txt"))
        do {
            try await ops.undo()
            XCTFail("the undo should have stopped")
        } catch {}
        XCTAssertEqual(box.names("A"), ["b.txt", "c.txt"])
        XCTAssertEqual(box.names("B"), ["x.txt"])
        let undoKind = await ops.undoKind
        let redoKind = await ops.redoKind
        XCTAssertEqual(undoKind, .move, "what is left stays undoable")
        XCTAssertEqual(redoKind, .move, "what was undone can be redone")
        try FileManager.default.moveItem(at: box.url("B/x.txt"), to: box.url("B/a.txt"))
        try await ops.undo()
        XCTAssertEqual(box.names("A"), ["a.txt", "b.txt", "c.txt"])
        XCTAssertEqual(box.names("B"), [])
    }

    // MARK: Put Back hears of every trashed item (N8)

    func testEveryTrashedItemIsReportedForPutBack() async throws {
        let ops = box.operations()
        var changes = ops.trashChanges.makeAsyncIterator()
        let one = try box.file("a/one.txt")
        let two = try box.file("a/two.txt")
        let trashed = try await ops.moveToTrash([one, two])
        for (original, place) in zip([one, two], trashed) {
            let change = await changes.next()
            XCTAssertEqual(change, .trashed(original: original, trashed: place, stamp: FileStamp.of(place)))
        }
        try await ops.undo()
        var left: [String] = []
        for _ in 0..<2 {
            guard case .left(let place)? = await changes.next() else { return XCTFail("undo was not reported") }
            left.append(place.path)
        }
        XCTAssertEqual(Set(left), Set(trashed.map(\.path)))
        try await ops.redo()
        for _ in 0..<2 {
            guard case .trashed(let original, _, let stamp)? = await changes.next() else { return XCTFail("redo was not reported") }
            XCTAssertTrue([one, two].contains(original))
            XCTAssertNotNil(stamp)
        }
    }

    func testAStoppedTrashStillReportsWhatWent() async throws {
        let folder = box.trashFolder
        let calls = Counter()
        let ops = FileOperations(trash: { url in
            guard calls.next() == 0 else { throw CocoaError(.fileWriteNoPermission) }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        var changes = ops.trashChanges.makeAsyncIterator()
        let one = try box.file("a/one.txt")
        let two = try box.file("a/two.txt")
        do {
            try await ops.moveToTrash([one, two])
            XCTFail("the second item should have failed")
        } catch {}
        let first = await changes.next()
        XCTAssertEqual(first, .trashed(original: one, trashed: folder.appendingPathComponent("one.txt"),
                                       stamp: FileStamp.of(folder.appendingPathComponent("one.txt"))))
        XCTAssertTrue(box.exists("a/two.txt"))
    }

    func testAStampTellsAnItemFromOneThatTookItsName() throws {
        let first = try box.file("t/r.pdf", "A")
        let stamp = FileStamp.of(first)
        try FileManager.default.moveItem(at: first, to: box.url("elsewhere.pdf"))
        try box.file("t/r.pdf", "B")
        XCTAssertNotEqual(FileStamp.of(box.url("t/r.pdf")), stamp)
        XCTAssertEqual(FileStamp.of(box.url("elsewhere.pdf")), stamp, "a move keeps the identity")
    }

    // MARK: Moves to another volume (N11)

    func testAMoveAcrossVolumesCopiesThenTrashesTheOriginal() async throws {
        try box.file("a/Project/one.txt", "1")
        let ops = box.operations()
        try await ops.moveAcrossVolumes(box.url("a/Project"), to: box.url("b-Project")) { _, _ in }
        XCTAssertEqual(box.text("b-Project/one.txt"), "1")
        XCTAssertFalse(box.exists("a/Project"))
        XCTAssertEqual(box.trashed, ["Project"], "the original goes to the Trash, never deleted")
    }

    func testAStoppedMoveAcrossVolumesLeavesTheOriginal() async throws {
        try box.file("a/Project/one.txt", "1")
        try box.file("a/Project/two.txt", "2")
        let ops = box.operations()
        do {
            try await ops.moveAcrossVolumes(box.url("a/Project"), to: box.url("b-Project")) { _, _ in throw CancellationError() }
            XCTFail("the move should have stopped")
        } catch {}
        XCTAssertEqual(box.names("a/Project"), ["one.txt", "two.txt"])
        XCTAssertFalse(box.exists("b-Project"))
        XCTAssertEqual(box.trashed, ["b-Project"], "the half copy goes to the Trash")
    }

    // MARK: Claiming a name (N1)

    func testReservedNamesAreNeverShared() throws {
        let folder = try box.folder("z")
        try box.file("z/Archive.zip", "the person's own")
        let first = try FileNaming.reserve("Archive.zip", in: folder)
        let second = try FileNaming.reserve("Archive.zip", in: folder)
        XCTAssertEqual(first.url.lastPathComponent, "Archive 2.zip")
        XCTAssertEqual(second.url.lastPathComponent, "Archive 3.zip")
        XCTAssertEqual(box.text("z/Archive.zip"), "the person's own")
        let made = try box.file("z/.working.zip", "zipped")
        try FileNaming.settle(made, onto: first)
        XCTAssertEqual(box.text("z/Archive 2.zip"), "zipped")
        // A released name goes only while it is still the empty file reserved.
        second.release()
        XCTAssertFalse(box.exists("z/Archive 3.zip"))
        let third = try FileNaming.reserve("Archive.zip", in: folder)
        try Data("written by someone".utf8).write(to: third.url)
        third.release()
        XCTAssertEqual(box.text("z/" + third.url.lastPathComponent), "written by someone")
        XCTAssertThrowsError(try FileNaming.settle(made, onto: third))
    }

    // MARK: Clutter (N13)

    func testClutterSkipsPackages() throws {
        try box.file("c/.DS_Store")
        try box.file("c/Tool.app/Contents/.DS_Store")
        try box.file("c/sub/.DS_Store")
        let found = try Clutter.find(in: box.url("c")).map { $0.path.replacingOccurrences(of: box.url("c").path + "/", with: "") }
        XCTAssertEqual(found, [".DS_Store", "sub/.DS_Store"])
        XCTAssertEqual(try Clutter.find(in: box.url("c/Tool.app")), [], "nothing inside a package is touched")
    }

    // MARK: Folder sizes (N7)

    func testFolderSizesKeepToTheirLimits() async throws {
        for i in 0..<30 { try box.file("p/f\(i).txt", "1") }
        let sizes = FolderSize()
        let tight = FolderSizeLimits(maxDepth: 64, maxEntries: 10, maxSeconds: 5, includeRemote: false)
        let none = await sizes.size(of: box.url("p"), limits: tight)
        XCTAssertNil(none, "past a limit there is no size")
        let notKept = await sizes.cached(box.url("p"))
        XCTAssertNil(notKept, "and nothing half measured is remembered")
        let shallow = FolderSizeLimits(maxDepth: 0, maxEntries: 1_000, maxSeconds: 5, includeRemote: false)
        try box.file("q/deep/x.txt", "1")
        let tooDeep = await sizes.size(of: box.url("q"), limits: shallow)
        XCTAssertNil(tooDeep)
        let full = await sizes.size(of: box.url("p"), limits: .listing)
        XCTAssertEqual(full?.files, 30)
    }

    func testCloudFoldersAreRemote() {
        XCTAssertTrue(FolderSize.isCloudPath("/Users/me/Library/CloudStorage/GoogleDrive-x/My Drive"))
        XCTAssertTrue(FolderSize.isCloudPath("/Users/me/Library/Mobile Documents"))
        XCTAssertFalse(FolderSize.isCloudPath("/Users/me/Documents/Library"))
        XCTAssertFalse(FolderSize.isRemote(box.root))
    }

    func testACancelledMeasurementStops() async throws {
        for i in 0..<200 { try box.file("p/\(i)/x.txt", "1") }
        let sizes = FolderSize()
        let folder = box.url("p")
        let task = Task { await sizes.size(of: folder, limits: .listing) }
        task.cancel()
        let result = await task.value
        // Either it finished before the cancel landed or it stopped with no size.
        if let result { XCTAssertEqual(result.files, 200) }
    }
}

/// A counter shared with a @Sendable trash closure.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value - 1
    }
}
