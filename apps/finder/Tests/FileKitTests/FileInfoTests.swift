import XCTest
@testable import FileKit

/// Names, volumes, selection summaries, clutter and recents.
final class FileInfoTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    // MARK: Naming

    func testKeepBothNames() throws {
        let folder = try box.folder("n")
        XCTAssertEqual(FileNaming.keepBoth("Report.pdf", in: folder), "Report 2.pdf")
        try box.file("n/Report 2.pdf")
        XCTAssertEqual(FileNaming.keepBoth("Report.pdf", in: folder), "Report 3.pdf")
        XCTAssertEqual(FileNaming.keepBoth("Report 2.pdf", in: folder), "Report 3.pdf")
        XCTAssertEqual(FileNaming.keepBoth("Folder", in: folder), "Folder 2")
        XCTAssertEqual(FileNaming.keepBoth("a.txt", in: folder, avoiding: ["a 2.txt"]), "a 3.txt")
    }

    func testDuplicateAndAvailableNames() throws {
        let folder = try box.folder("n")
        XCTAssertEqual(FileNaming.duplicate("Report.pdf", in: folder), "Report copy.pdf")
        try box.file("n/Report copy.pdf")
        XCTAssertEqual(FileNaming.duplicate("Report.pdf", in: folder), "Report copy 2.pdf")
        XCTAssertEqual(FileNaming.duplicate("Report.pdf", in: folder, avoiding: ["Report copy 2.pdf"]), "Report copy 3.pdf")
        XCTAssertEqual(FileNaming.available("free.txt", in: folder), "free.txt")
        XCTAssertEqual(FileNaming.available("Report copy.pdf", in: folder), "Report copy 2.pdf")
    }

    func testValidNames() {
        XCTAssertTrue(FileNaming.isValid("Notes 2026.md"))
        XCTAssertFalse(FileNaming.isValid(""))
        XCTAssertFalse(FileNaming.isValid(".."))
        XCTAssertFalse(FileNaming.isValid("a/b"))
        XCTAssertFalse(FileNaming.isValid(String(repeating: "x", count: 256)))
    }

    // MARK: Volumes

    func testMountedVolumesIncludeTheStartupDisk() throws {
        let volumes = VolumeInfo.mounted()
        let root = try XCTUnwrap(volumes.first { $0.isRoot })
        XCTAssertGreaterThan(root.totalBytes, 0)
        XCTAssertGreaterThan(root.availableBytes, 0)
        XCTAssertLessThanOrEqual(root.availableBytes, root.totalBytes)
        XCTAssertGreaterThanOrEqual(root.availableBytes, root.freeBytes)
        XCTAssertFalse(root.canEject)
        XCTAssertFalse(root.isNetwork)
        XCTAssertFalse(root.name.isEmpty)
        XCTAssertEqual(root.id, root.url)
    }

    func testVolumeContainingAFile() throws {
        let file = try box.file("v.txt")
        let volume = try XCTUnwrap(VolumeInfo.containing(file))
        XCTAssertGreaterThan(volume.totalBytes, 0)
    }

    func testStartupDiskCannotBeEjected() async throws {
        let root = try XCTUnwrap(VolumeInfo.mounted().first { $0.isRoot })
        do {
            try await VolumeInfo.eject(root)
            XCTFail("ejected the startup disk")
        } catch {
            XCTAssertEqual(error as? VolumeInfo.Failure, .notEjectable(root.name))
        }
    }

    // MARK: Selection

    func testSelectionSummary() async throws {
        let a = try box.file("s/a.txt", "1234")
        try box.file("s/inner/b.txt", "12")
        let folder = box.url("s/inner")
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: a.path)
        try (a as NSURL).setResourceValue(["Red", "Work"], forKey: .tagNamesKey)
        try (folder as NSURL).setResourceValue(["Work"], forKey: .tagNamesKey)

        let summary = await SelectionSummary.make(for: [a, folder])
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.files, 1)
        XCTAssertEqual(summary.folders, 1)
        XCTAssertEqual(summary.totalBytes, 6)
        XCTAssertEqual(summary.kinds.values.reduce(0, +), 2)
        XCTAssertEqual(summary.kinds.count, 2)
        XCTAssertEqual(summary.oldest, old)
        XCTAssertNotNil(summary.newest)
        XCTAssertEqual(summary.commonTags, ["Work"])
        XCTAssertEqual(summary.commonParent?.path, box.url("s").path)
    }

    func testCommonParent() {
        let parent = SelectionSummary.commonParent(of: [
            URL(fileURLWithPath: "/Users/me/Docs/a/x.txt"),
            URL(fileURLWithPath: "/Users/me/Docs/b/y.txt"),
        ])
        XCTAssertEqual(parent?.path, "/Users/me/Docs")
        XCTAssertNil(SelectionSummary.commonParent(of: []))
    }

    // MARK: Clutter

    /// "._" files show up on shared and external drives; on the Mac's own disk
    /// macOS keeps them out of listings, so the disk part uses .DS_Store.
    func testClutterGoesToTheTrash() async throws {
        try box.file("c/.DS_Store")
        try box.file("c/report.docx")
        try box.file("c/deep/.DS_Store")
        XCTAssertTrue(Clutter.isClutter(".DS_Store"))
        XCTAssertTrue(Clutter.isClutter("._report.docx"))
        XCTAssertFalse(Clutter.isClutter("report.docx"))
        XCTAssertFalse(Clutter.isClutter("_report.docx"))
        XCTAssertEqual(Clutter.find(in: box.url("c"), recursive: false).map(\.lastPathComponent), [".DS_Store"])
        XCTAssertEqual(Clutter.find(in: box.url("c")).count, 2)

        let ops = box.operations()
        let trashed = try await Clutter.clean(in: box.url("c"), using: ops)
        XCTAssertEqual(trashed.count, 2)
        XCTAssertEqual(box.names("c"), ["deep", "report.docx"])
        try await ops.undo()
        XCTAssertEqual(box.names("c"), [".DS_Store", "deep", "report.docx"])
    }

    // MARK: Recents

    func testRecentsAreNewestFirstAndUnique() async throws {
        let log = box.url("support/recents.json")
        let one = try box.file("r/one.txt")
        let two = try box.file("r/two.txt")
        let recents = Recents(file: log, limit: 2)
        try await recents.record(one, at: Date(timeIntervalSince1970: 100))
        try await recents.record(two, at: Date(timeIntervalSince1970: 200))
        try await recents.record(one, at: Date(timeIntervalSince1970: 300))
        let list = await recents.list()
        XCTAssertEqual(list.map(\.path), [one.path, two.path])
        XCTAssertEqual(list.first?.opened, Date(timeIntervalSince1970: 300))

        let reloaded = Recents(file: log, limit: 2)
        let again = await reloaded.list()
        XCTAssertEqual(again, list)

        try await reloaded.record(try box.file("r/three.txt"))
        let capped = await reloaded.list()
        XCTAssertEqual(capped.count, 2)
        XCTAssertEqual(capped.last?.path, one.path)
    }

    func testRecentsDropMissingAndClear() async throws {
        let recents = Recents(file: box.url("support/recents.json"))
        let file = try box.file("r/gone.txt")
        try await recents.record(file)
        try FileManager.default.removeItem(at: file)
        let visible = await recents.list()
        XCTAssertTrue(visible.isEmpty)
        let all = await recents.list(includingMissing: true)
        XCTAssertEqual(all.map(\.url.path), [file.path])
        try await recents.remove(file)
        let removed = await recents.list(includingMissing: true)
        XCTAssertTrue(removed.isEmpty)
        try await recents.record(file)
        try await recents.clear()
        let cleared = await recents.list(includingMissing: true)
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertTrue(Recents.defaultFile.path.hasSuffix("Application Support/Log Pose/recents.json"))
    }
}
