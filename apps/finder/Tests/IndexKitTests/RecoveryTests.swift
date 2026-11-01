import CoreServices
import XCTest
@testable import IndexKit

/// The FSEvents recovery matrix: what a loaded snapshot and each event flag lead to.
final class RecoveryTests: XCTestCase {
    private let root = "/Users/me"

    private func startup(
        count: Int = 1_000, complete: Bool = true, stored: UInt64 = 500, current: UInt64 = 900,
        storedVolumes: [String: String]? = nil, currentVolumes: [String: String]? = nil
    ) -> IndexRecovery.Startup {
        IndexRecovery.startup(
            count: count, complete: complete, storedEventID: stored, currentEventID: current, roots: [root],
            storedVolumes: storedVolumes ?? [root: "VOL-A"], currentVolumes: currentVolumes ?? [root: "VOL-A"]
        )
    }

    func testAGoodSnapshotResumesFromItsEvent() {
        XCTAssertEqual(startup(), .resume(since: 500))
        XCTAssertEqual(startup(stored: 900, current: 900), .resume(since: 900), "no events since is fine")
    }

    func testNothingSavedMeansAFirstBuild() {
        XCTAssertEqual(startup(count: 0), .build)
        XCTAssertEqual(startup(count: 0, complete: false), .build)
    }

    func testAnUnfinishedSnapshotIsWalkedAgain() {
        XCTAssertEqual(startup(complete: false), .rebuild(.incomplete))
    }

    func testAnotherDiskMeansAFullRebuild() {
        XCTAssertEqual(startup(currentVolumes: [root: "VOL-B"]), .rebuild(.volumeChanged(root: root)))
    }

    func testAnEventCounterBehindTheSnapshotMeansAFullRebuild() {
        XCTAssertEqual(startup(stored: 900, current: 100), .rebuild(.eventIDWentBackwards))
    }

    func testNoStoredEventMeansAFullRebuild() {
        XCTAssertEqual(startup(stored: 0), .rebuild(.noHistory))
    }

    func testSnapshotsWithoutVolumesStillResume() {
        // Sight's and Nexus's snapshots from before the service saved no UUIDs.
        XCTAssertEqual(startup(storedVolumes: [:]), .resume(since: 500))
        XCTAssertEqual(startup(currentVolumes: [:]), .resume(since: 500), "a volume that cannot be read is not a new one")
    }

    func testEventFlags() {
        func action(_ flag: Int, _ path: String = "/Users/me/Documents") -> IndexRecovery.Event {
            IndexRecovery.event(path: path, flags: FSEventStreamEventFlags(flag))
        }
        XCTAssertEqual(action(kFSEventStreamEventFlagNone), .folder("/Users/me/Documents"))
        XCTAssertEqual(action(kFSEventStreamEventFlagItemCreated), .folder("/Users/me/Documents"))
        XCTAssertEqual(action(kFSEventStreamEventFlagMustScanSubDirs), .subtree("/Users/me/Documents"))
        XCTAssertEqual(action(kFSEventStreamEventFlagRootChanged, root), .subtree(root))
        XCTAssertEqual(action(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped), .roots)
        XCTAssertEqual(action(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped), .roots)
        XCTAssertEqual(action(kFSEventStreamEventFlagEventIdsWrapped), .rebuild)
        XCTAssertEqual(action(kFSEventStreamEventFlagHistoryDone, ""), .ignore)
        XCTAssertEqual(action(kFSEventStreamEventFlagNone, ""), .ignore)
    }

    func testDroppedEventsRescanEveryRoot() {
        let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped)
        let plain = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)
        let changes = FolderWatcher.changes(
            from: [("/", dropped, 10), ("/a/one", plain, 11), ("/b/two", plain, 12)],
            roots: ["/a", "/b"]
        )
        XCTAssertEqual(changes, [FolderChange(path: "/a", recursive: true), FolderChange(path: "/b", recursive: true)])
    }

    func testWeeklySweep() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertFalse(IndexRecovery.sweepDue(last: nil, now: now), "the first run only records the date")
        XCTAssertFalse(IndexRecovery.sweepDue(last: now.addingTimeInterval(-6 * 86_400), now: now))
        XCTAssertTrue(IndexRecovery.sweepDue(last: now.addingTimeInterval(-7 * 86_400), now: now))
        XCTAssertTrue(IndexRecovery.sweepDue(last: now.addingTimeInterval(3_600), now: now), "a clock set back")
    }

    func testAWholeRootFromTheWatcherIsWalkedInTheBackground() async throws {
        let folder = try Fixture.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try Fixture.make("Docs/first.txt", in: folder)
        let index = FileIndex(roots: [folder])
        await index.build()
        try Fixture.make("Docs/second.txt", in: folder)
        await index.applyWatched(WatchBatch(changes: [FolderChange(path: folder, recursive: true)], eventID: 0))
        var found: [String] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
            found = await index.search("second").map(\.path)
        }
        XCTAssertEqual(found, [folder + "/Docs/second.txt"])
        let first = await index.search("first").map(\.path)
        XCTAssertEqual(first, [folder + "/Docs/first.txt"], "the old entries answered throughout")
    }
}
