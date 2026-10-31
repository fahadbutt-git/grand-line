import CoreServices
import XCTest
@testable import IndexKit

final class WatcherTests: XCTestCase {
    func testCoalesceMergesAndSorts() {
        let changes = FolderChange.coalesce([
            FolderChange(path: "/a/b/"),
            FolderChange(path: "/a/b"),
            FolderChange(path: "/z"),
            FolderChange(path: "/a/c"),
        ])
        XCTAssertEqual(changes, [FolderChange(path: "/a/b"), FolderChange(path: "/a/c"), FolderChange(path: "/z")])
    }

    func testRecursiveChangeAbsorbsChangesBelow() {
        let changes = FolderChange.coalesce([
            FolderChange(path: "/a/b/c"),
            FolderChange(path: "/a/b", recursive: true),
            FolderChange(path: "/a/bc"),
            FolderChange(path: "/a/b"),
        ])
        XCTAssertEqual(changes, [FolderChange(path: "/a/b", recursive: true), FolderChange(path: "/a/bc")])
    }

    func testIsInside() {
        XCTAssertTrue(FolderChange.isInside("/a/b", "/a"))
        XCTAssertTrue(FolderChange.isInside("/a", "/a"))
        XCTAssertTrue(FolderChange.isInside("/a", "/"))
        XCTAssertFalse(FolderChange.isInside("/ab", "/a"))
        XCTAssertFalse(FolderChange.isInside("/a", "/a/b"))
    }

    func testEventFlags() {
        let plain = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)
        let deep = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let done = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        let changes = FolderWatcher.changes(from: [
            ("/x/one/", plain, 1),
            ("/x/two/", deep, 2),
            ("", done, 3),
        ])
        XCTAssertEqual(changes, [FolderChange(path: "/x/one"), FolderChange(path: "/x/two", recursive: true)])
    }

    func testRealPath() throws {
        XCTAssertEqual(FolderWatcher.realPath("/tmp"), "/private/tmp")
        XCTAssertEqual(FolderWatcher.realPath("/no/such/place/"), "/no/such/place")
        XCTAssertEqual(FolderWatcher.realPath("~"), FolderWatcher.realPath(NSHomeDirectory()))
    }

    func testEventIDsMoveForward() {
        let watcher = FolderWatcher(paths: ["/tmp"], since: 7)
        XCTAssertEqual(watcher.latestEventID, 7)
        XCTAssertEqual(watcher.paths, ["/private/tmp"])
        XCTAssertGreaterThan(FolderWatcher.currentEventID, 0)
    }

    func testReportsARealChange() async throws {
        let folder = try Fixture.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let watcher = FolderWatcher(paths: [folder], latency: 0.1)
        XCTAssertTrue(watcher.start())
        try await Task.sleep(nanoseconds: 300_000_000)
        try Fixture.make("new.txt", in: folder)
        let batch = await firstBatch(watcher.changes, within: 15)
        watcher.stop()
        let paths = try XCTUnwrap(batch).map(\.path)
        XCTAssertTrue(paths.contains { FolderChange.isInside($0, folder) }, "\(paths)")
    }

    func testIndexFollowsTheDisk() async throws {
        let folder = try Fixture.folder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let index = FileIndex(roots: [folder])
        await index.build()
        await index.startWatching(latency: 0.1)
        try await Task.sleep(nanoseconds: 300_000_000)
        try Fixture.make("Watched/arrived.txt", in: folder)
        var found: [IndexMatch] = []
        for _ in 0..<150 where found.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            found = await index.search("arrived")
        }
        await index.stopWatching()
        XCTAssertEqual(found.first?.path, folder + "/Watched/arrived.txt")
    }
}
