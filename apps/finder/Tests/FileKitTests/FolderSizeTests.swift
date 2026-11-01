import IndexKit
import XCTest
@testable import FileKit

final class FolderSizeTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    func testSumsFilesAndFolders() async throws {
        try box.file("p/a.txt", "12345")
        try box.file("p/sub/b.txt", "123")
        try box.file("p/sub/deeper/c.txt", "1")
        let sizes = FolderSize()
        let total = await sizes.size(of: box.url("p"))
        XCTAssertEqual(total.bytes, 9)
        XCTAssertEqual(total.files, 3)
        XCTAssertEqual(total.folders, 2)
        XCTAssertGreaterThanOrEqual(total.allocatedBytes, 0)
        let sub = await sizes.cached(box.url("p/sub"))
        XCTAssertEqual(sub?.bytes, 4)
    }

    func testTheCacheKeepsTheShallowestFoldersWithinItsLimit() async throws {
        for i in 0..<12 {
            try box.file("p/f\(i)/deep/deeper/x.txt", "1")
        }
        let sizes = FolderSize(maxEntries: 10)
        let total = await sizes.size(of: box.url("p"))
        XCTAssertEqual(total.files, 12)
        let count = await sizes.count
        XCTAssertLessThanOrEqual(count, 10)
        // The folder asked for is always kept, so asking again is instant.
        let again = await sizes.cached(box.url("p"))
        XCTAssertEqual(again, total)
        // The deepest went first.
        let deepest = await sizes.cached(box.url("p/f0/deep/deeper"))
        XCTAssertNil(deepest)
    }

    func testCacheUntilAWatcherEvent() async throws {
        try box.file("p/sub/b.txt", "123")
        let sizes = FolderSize()
        let first = await sizes.size(of: box.url("p"))
        try box.file("p/sub/more.txt", "4567")
        let cached = await sizes.size(of: box.url("p"))
        XCTAssertEqual(cached, first)

        await sizes.invalidate([FolderChange(path: box.url("p/sub").path)])
        let parentGone = await sizes.cached(box.url("p"))
        XCTAssertNil(parentGone)
        let fresh = await sizes.size(of: box.url("p"))
        XCTAssertEqual(fresh.bytes, 7)
    }

    func testRecursiveEventClearsBelow() async throws {
        try box.file("p/sub/b.txt", "123")
        let sizes = FolderSize()
        _ = await sizes.size(of: box.url("p"))
        await sizes.invalidate([FolderChange(path: box.url("p").path, recursive: true)])
        let sub = await sizes.cached(box.url("p/sub"))
        XCTAssertNil(sub)
    }

    func testFiftyThousandFiles() async throws {
        let fileManager = FileManager.default
        for folder in 0..<50 {
            let dir = box.url("big/\(folder)")
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<1_000 {
                fileManager.createFile(atPath: dir.appendingPathComponent("\(i).txt").path, contents: Data("ab".utf8))
            }
        }
        let start = Date()
        let total = await FolderSize().size(of: box.url("big"))
        print("measured 50,000 files in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        XCTAssertEqual(total.files, 50_000)
        XCTAssertEqual(total.bytes, 100_000)
        XCTAssertEqual(total.folders, 50)
    }
}
