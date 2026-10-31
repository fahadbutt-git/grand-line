import XCTest
@testable import IndexKit

/// A first build: the busiest folders first, Google Drive last, searchable while
/// it runs, saved along the way, and honest about folders it could not read.
final class BuildOrderTests: XCTestCase {
    private var home = ""

    override func setUpWithError() throws {
        home = try Fixture.folder()
        for path in [
            "Applications/tool.txt", "Desktop/desk.txt", "Documents/doc.txt", "Downloads/Conj Flap/",
            "Downloads/Lid Study - CONJ/", "Music/song.txt",
            "Library/CloudStorage/GoogleDrive-me@example.com/My Drive/drive.txt",
        ] {
            try Fixture.make(path, in: home)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: home + "/Desktop")
        try? FileManager.default.removeItem(atPath: home)
    }

    func testBusyFoldersFirstAndCloudStorageLast() {
        let built = FolderScanner.build(roots: [home], exclusions: .standard, order: .home(home))
        let storage = built.storage
        func position(_ name: String) -> Int {
            (0..<storage.count).first { storage.name($0) == name } ?? -1
        }
        XCTAssertLessThan(position("Conj Flap"), position("desk.txt"))
        XCTAssertLessThan(position("desk.txt"), position("doc.txt"))
        XCTAssertLessThan(position("doc.txt"), position("tool.txt"))
        XCTAssertLessThan(position("song.txt"), position("drive.txt"))
        XCTAssertLessThan(position("tool.txt"), position("drive.txt"))
        XCTAssertTrue(built.complete)
        XCTAssertEqual(storage.liveCount, FolderScanner.build(roots: [home], exclusions: .standard).storage.liveCount)
    }

    func testPartsArePublishedWhileWalking() {
        var parts: [BuiltIndex] = []
        let built = FolderScanner.build(roots: [home], exclusions: .standard, order: .home(home), interval: 0) { parts.append($0) }
        XCTAssertFalse(parts.isEmpty)
        XCTAssertTrue(parts.allSatisfy { !$0.complete })
        XCTAssertEqual(parts.map(\.step), Array(1...parts.count))
        XCTAssertGreaterThan(built.step, parts.count)
        let early = parts.first { part in (0..<part.storage.count).contains { part.storage.name($0) == "Conj Flap" } }
        XCTAssertNotNil(early)
        XCTAssertFalse((0..<early!.storage.count).contains { early!.storage.name($0) == "drive.txt" })
    }

    func testABuiltIndexIsCompleteAndSavesThatItIs() async throws {
        let index = FileIndex(roots: [home], order: .home(home))
        var complete = await index.isComplete
        XCTAssertFalse(complete)
        let snapshot = URL(fileURLWithPath: home + "-index.bin")
        defer { try? FileManager.default.removeItem(at: snapshot) }
        await index.build(savingTo: snapshot)
        complete = await index.isComplete
        XCTAssertTrue(complete)
        let found = await index.search("conj").map(\.name).sorted()
        XCTAssertEqual(found, ["Conj Flap", "Lid Study - CONJ"])
        let loaded = try FileIndex.load(from: snapshot)
        complete = await loaded.isComplete
        XCTAssertTrue(complete, "the build saved its snapshot when done")
    }

    func testAnUnfinishedSnapshotLoadsAsUnfinished() async throws {
        let storage = Fixture.storage(["Downloads/Conj Flap/"])
        let index = FileIndex(roots: [Fixture.root], exclusions: .standard, storage: storage, lastEventID: 0, complete: false)
        let snapshot = URL(fileURLWithPath: home + "-partial.bin")
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try await index.save(to: snapshot)
        let loaded = try FileIndex.load(from: snapshot)
        let complete = await loaded.isComplete
        XCTAssertFalse(complete)
        let found = await loaded.search("conj").map(\.name)
        XCTAssertEqual(found, ["Conj Flap"], "what was saved can be searched before the build finishes")
    }

    func testFoldersItMayNotReadAreReported() async throws {
        try XCTSkipIf(getuid() == 0, "root can read every folder")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: home + "/Desktop")
        let index = FileIndex(roots: [home], order: .home(home))
        await index.build()
        let unreadable = await index.unreadable
        XCTAssertEqual(unreadable, [home + "/Desktop"])
    }
}
