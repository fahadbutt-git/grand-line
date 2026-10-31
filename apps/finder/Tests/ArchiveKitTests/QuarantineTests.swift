import XCTest
@testable import ArchiveKit

/// Security notes L1 and L2: what comes out of a quarantined archive stays
/// quarantined, and Quick Look's temporary copies do not pile up.
final class QuarantineTests: XCTestCase {
    private var space: Workspace!
    private let flag = Data("0081;65f00000;Safari;".utf8)

    override func setUpWithError() throws {
        space = try Workspace()
        try space.file("src/README.md", "read me")
        try space.file("src/Tools/run.command", "echo hi")
        try space.file("src/Tools/inner/more.txt", "more")
    }

    override func tearDown() {
        space.remove()
    }

    func testExtractedItemsTakeTheArchivesFlag() throws {
        let archive = try space.zip("src", to: "download.zip")
        XCTAssertTrue(Quarantine.set(flag, on: archive))
        XCTAssertEqual(Quarantine.value(of: archive), flag)
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let made = try Archive.extract(["README.md", "Tools"], from: archive, to: out)
        XCTAssertEqual(made.map(\.lastPathComponent), ["README.md", "Tools"])
        for relative in ["README.md", "Tools", "Tools/run.command", "Tools/inner", "Tools/inner/more.txt"] {
            XCTAssertEqual(Quarantine.value(of: out.appendingPathComponent(relative)), flag, relative)
        }
    }

    func testAnArchiveWithoutTheFlagAddsNone() throws {
        let archive = try space.zip("src", to: "local.zip")
        XCTAssertNil(Quarantine.value(of: archive))
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let made = try Archive.extract(["README.md"], from: archive, to: out)
        XCTAssertNil(Quarantine.value(of: made[0]))
    }

    func testPreviewsAreQuarantinedAndCleaned() throws {
        let archive = try space.zip("src", to: "download.zip")
        Quarantine.set(flag, on: archive)
        let root = space.url("previews")
        let preview = try Archive.preview("README.md", from: archive, in: root)
        XCTAssertEqual(space.text(preview), "read me")
        XCTAssertTrue(preview.path.hasPrefix(root.path))
        XCTAssertEqual(Quarantine.value(of: preview), flag)
        XCTAssertEqual(Archive.TemporaryFolder.clean(root), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
        XCTAssertEqual(Archive.TemporaryFolder.clean(root), 0, "nothing left to clean")
        XCTAssertEqual(Archive.TemporaryFolder.clean(space.url("never made")), 0)
    }

    func testOnlyOldOpenedCopiesAreCleaned() throws {
        let archive = try space.zip("src", to: "bundle.zip")
        let root = space.url("opened")
        let old = try Archive.preview("README.md", from: archive, in: root)
        let fresh = try Archive.preview("README.md", from: archive, in: root)
        let lastWeek = Date().addingTimeInterval(-7 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: lastWeek], ofItemAtPath: old.deletingLastPathComponent().path)
        XCTAssertEqual(Archive.TemporaryFolder.clean(root, before: Date().addingTimeInterval(-86_400)), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testQuickLooksFolderIsArchivePreviewInTMPDIR() {
        XCTAssertEqual(Archive.TemporaryFolder.quickLook.lastPathComponent, "Archive Preview")
        XCTAssertEqual(Archive.TemporaryFolder.quickLook.deletingLastPathComponent().standardizedFileURL,
                       FileManager.default.temporaryDirectory.standardizedFileURL)
    }
}
