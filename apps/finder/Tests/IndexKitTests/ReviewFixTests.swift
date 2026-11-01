import CoreServices
import XCTest
@testable import IndexKit

/// The stored event covers only what was applied, exclusions are rules,
/// excluded trees cost nothing, and opens are bounded.
final class IndexReviewFixTests: XCTestCase {
    private var folder = ""

    override func setUpWithError() throws {
        folder = try Fixture.folder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: folder)
    }

    // MARK: The stored event

    func testATaggedWatcherCarriesTheNewestEventOfEachBatch() async {
        let (changes, plain) = AsyncStream.makeStream(of: [FolderChange].self)
        let (batches, tagged) = AsyncStream.makeStream(of: WatchBatch.self)
        let box = WatcherBox(continuation: plain, latest: 3, roots: [], batches: tagged)
        let plainFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)
        let done = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        box.receive([("/x/one/", plainFlags, 5), ("/x/two/", plainFlags, 9)])
        box.receive([("", done, 12)])
        tagged.finish()
        plain.finish()
        var seen: [WatchBatch] = []
        for await batch in batches { seen.append(batch) }
        XCTAssertEqual(seen, [
            WatchBatch(changes: [FolderChange(path: "/x/one"), FolderChange(path: "/x/two")], eventID: 9),
            WatchBatch(changes: [], eventID: 12),
        ], "a batch that changes nothing still moves the event on")
        var untagged = 0
        for await _ in changes { untagged += 1 }
        XCTAssertEqual(untagged, 0, "only one stream is fed")
        XCTAssertEqual(box.latestEventID, 12)
    }

    func testOnlyAppliedEventsAreSaved() async throws {
        let index = Fixture.index(["a/notes.txt"])
        await index.apply([])
        let untouched = await index.eventID
        XCTAssertEqual(untouched, 0, "applying changes alone does not claim any event")
        await index.applyWatched(WatchBatch(changes: [], eventID: 42))
        let applied = await index.eventID
        XCTAssertEqual(applied, 42)
        await index.applyWatched(WatchBatch(changes: [], eventID: 7))
        let still = await index.eventID
        XCTAssertEqual(still, 42, "never backwards")
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("names.index")
        try await index.save(to: snapshot)
        let saved = try await FileIndex.load(from: snapshot).eventID
        XCTAssertEqual(saved, 42)
    }

    // MARK: Excluded trees

    func testChangesInsideExcludedTreesAreDroppedBeforeAnyWork() async {
        // Made-up paths: a rescan of /Index/a would find no such folder and
        // remove it, so a change that reached a rescan would show.
        let index = Fixture.index(["a/notes.txt", "a/sub/x.txt"])
        let before = await index.count
        await index.apply([
            FolderChange(path: "/Index/a/node_modules/pkg/lib"),
            FolderChange(path: "/Index/a/.git/objects/ab"),
            FolderChange(path: "/Index/a/Viewer.app/Contents/Resources"),
            FolderChange(path: "/Index/a/DerivedData/Build", recursive: true),
        ])
        let after = await index.count
        XCTAssertEqual(after, before)
        let notes = await index.search("notes")
        XCTAssertEqual(notes.first?.path, "/Index/a/notes.txt")
        let excluded = await index.isExcluded("/Index/a/node_modules/x")
        let kept = await index.isExcluded("/Index/a/sub")
        let root = await index.isExcluded("/Index")
        XCTAssertTrue(excluded)
        XCTAssertFalse(kept)
        XCTAssertFalse(root)
    }

    func testManyNewFoldersUnderOneParentAreAllFound() async throws {
        try Fixture.make("Docs/start.txt", in: folder)
        let index = FileIndex(roots: [folder])
        await index.build()
        var changes: [FolderChange] = []
        for i in 0..<40 {
            try Fixture.make("Docs/new \(i)/deep/file \(i).txt", in: folder)
            changes.append(FolderChange(path: folder + "/Docs/new \(i)/deep"))
        }
        await index.apply(changes)
        let found = await index.search("file", limit: 100)
        XCTAssertEqual(found.count, 40)
    }

    // MARK: Exclusions are rules

    func testLibraryIsARuleNotAListOfNames() {
        let rules = IndexExclusions.home("/Users/me", libraryNames: [])
        XCTAssertTrue(rules.skips(path: "/Users/me/Library/Made Next Week"))
        XCTAssertTrue(rules.skips(path: "/Users/me/Library/prefs.plist"))
        XCTAssertFalse(rules.skips(path: "/Users/me/Library/CloudStorage"))
        XCTAssertFalse(rules.skips(path: "/Users/me/Library"))
        XCTAssertFalse(rules.skips(path: "/Users/me/Documents"))
        XCTAssertTrue(rules.excludes("/Users/me/Library/Made Next Week/deep/file.db"))
        XCTAssertFalse(rules.excludes("/Users/me/Library/CloudStorage/Drive/a.docx"))
        XCTAssertFalse(rules.excludes("/Users/me/Library"))
        XCTAssertFalse(rules.excludes("/Users/me/Libraryish/a"))
        XCTAssertTrue(IndexExclusions(paths: ["/x/y"]).excludes("/x/y/z"))
        XCTAssertTrue(rules.hasPathRules)
        XCTAssertFalse(IndexExclusions.standard.hasPathRules)
    }

    func testAFolderMadeInLibraryLaterIsLeftOut() async throws {
        let home = folder
        try Fixture.make("Library/CloudStorage/Drive/conj drive.docx", in: home)
        try Fixture.make("Documents/conj notes.txt", in: home)
        let index = FileIndex(roots: [home], exclusions: IndexExclusions.home(home))
        await index.build()
        // An app made this after the index started.
        try Fixture.make("Library/Vendor/conj vendor.db", in: home)
        await index.apply([FolderChange(path: home + "/Library"), FolderChange(path: home + "/Library/Vendor", recursive: true)])
        let names = await index.search("conj").map(\.name).sorted()
        XCTAssertEqual(names, ["conj drive.docx", "conj notes.txt"])
        // And a walk from scratch leaves it out too.
        await index.build()
        let walked = await index.search("conj").map(\.name).sorted()
        XCTAssertEqual(walked, ["conj drive.docx", "conj notes.txt"])
    }

    func testPruningAppliesTheRulesToAnySnapshot() async {
        let storage = Fixture.storage(["Library/Mail/inbox.eml", "Library/CloudStorage/Drive/drive.docx", "Library/prefs.plist", "Docs/notes.txt"])
        let index = FileIndex(roots: ["/Index"], exclusions: IndexExclusions.home("/Index", libraryNames: []), storage: storage, lastEventID: 0)
        let removed = await index.pruneExcluded()
        XCTAssertEqual(removed, 3, "Mail, its message and prefs.plist")
        for gone in ["inbox", "prefs", "mail"] {
            let found = await index.search(gone)
            XCTAssertTrue(found.isEmpty, gone)
        }
        let drive = await index.search("drive.docx")
        XCTAssertEqual(drive.first?.path, "/Index/Library/CloudStorage/Drive/drive.docx")
        let again = await index.pruneExcluded()
        XCTAssertEqual(again, 0)
    }

    // MARK: Opens are bounded

    func testOnlyIndexedPathsAreRemembered() async {
        let index = Fixture.index(["a/notes.txt"])
        await index.noteOpened("/Somewhere/else.txt")
        await index.noteOpened("/Index/a/missing.txt")
        let none = await index.usageCount
        XCTAssertEqual(none, 0)
        let clean = await index.hasUnsavedChanges
        XCTAssertFalse(clean)
        await index.noteOpened("/Index/a/notes.txt")
        let one = await index.usageCount
        XCTAssertEqual(one, 1)
    }

    func testOpensAreCappedAndAgeOut() async {
        let count = FileIndex.maxUsage + 10
        let index = Fixture.index((0..<count).map { "d\($0)/" })
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<count {
            await index.noteOpened("/Index/d\(i)", at: start.addingTimeInterval(Double(i)))
        }
        let capped = await index.usageCount
        XCTAssertEqual(capped, FileIndex.maxUsage)
        await index.trimUsage(now: start.addingTimeInterval(FileIndex.usageLifetime + 100))
        let aged = await index.usageCount
        XCTAssertEqual(aged, FileIndex.maxUsage + 10 - 101, "opens older than the lifetime go")
    }
}
