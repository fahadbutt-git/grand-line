import XCTest
@testable import IndexKit

/// What the shared index service relies on: the stored event and volume, the
/// choice of snapshot to adopt, scoped searches with a narrowing per caller,
/// and the result encoding.
final class SharedIndexTests: XCTestCase {
    private var folder = ""

    override func setUpWithError() throws {
        folder = try Fixture.folder()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: folder)
    }

    // MARK: Event ID and volume persistence

    func testEventIDAndVolumesRoundTrip() async throws {
        let storage = Fixture.storage(["a/one.txt"])
        let index = FileIndex(
            roots: ["/Index"], exclusions: .standard, storage: storage, lastEventID: 4_242,
            volumes: ["/Index": "11111111-2222-3333-4444-555555555555"]
        )
        let snapshot = URL(fileURLWithPath: folder).appendingPathComponent("names.index")
        try await index.save(to: snapshot)
        let loaded = try FileIndex.load(from: snapshot)
        let event = await loaded.eventID
        let volumes = await loaded.volumeUUIDs
        XCTAssertEqual(event, 4_242)
        XCTAssertEqual(volumes, ["/Index": "11111111-2222-3333-4444-555555555555"])
        let header = try IndexSnapshot.header(of: Data(contentsOf: snapshot))
        XCTAssertEqual(header, IndexSnapshot.Header(version: IndexSnapshot.version, lastEventID: 4_242, complete: true, roots: ["/Index"]))
    }

    func testABuildRecordsTheVolumeAndTheEventItStartedAt() async throws {
        try Fixture.make("Docs/letter.docx", in: folder)
        let before = FolderWatcher.currentEventID
        let index = FileIndex(roots: [folder])
        await index.build()
        let event = await index.eventID
        let volumes = await index.volumeUUIDs
        XCTAssertGreaterThanOrEqual(event, before)
        XCTAssertNotNil(volumes[folder], "the build notes the volume of its root")
        XCTAssertEqual(volumes[folder], FolderWatcher.volumeUUID(of: folder))
    }

    func testTheSavedEventMovesForwardWithTheWatcher() async throws {
        try Fixture.make("Docs/start.txt", in: folder)
        let index = FileIndex(roots: [folder])
        await index.build()
        let built = await index.eventID
        await index.startWatching(latency: 0.1)
        try await Task.sleep(nanoseconds: 300_000_000)
        try Fixture.make("Docs/later.txt", in: folder)
        var found: [IndexMatch] = []
        for _ in 0..<150 where found.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            found = await index.search("later")
        }
        let snapshot = URL(fileURLWithPath: folder + "-snapshot.index")
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try await index.save(to: snapshot)
        await index.stopWatching()
        XCTAssertFalse(found.isEmpty)
        let saved = try await FileIndex.load(from: snapshot).eventID
        XCTAssertGreaterThan(saved, built, "the next start replays only what came after this")
        let dirty = await index.hasUnsavedChanges
        XCTAssertFalse(dirty)
    }

    // MARK: Composed and decomposed names

    func testDecomposedNamesMatchComposedQueries() async {
        let decomposed = "Re\u{0301}sume\u{0301} conj.pdf"
        let index = Fixture.index(["Docs/" + decomposed, "Docs/E\u{0301}COLE notes.txt"])
        for query in ["résumé", "re\u{0301}sume\u{0301}", "resume", "RÉSUMÉ"] {
            let found = await index.search(query)
            XCTAssertEqual(found.first?.name, decomposed, query)
        }
        let found = await index.search("resume")
        // R, é (two UTF-16 units decomposed), s, u, m, é (two again).
        XCTAssertEqual(found.first?.highlights, [0..<8])
        let school = await index.search("école")
        XCTAssertEqual(school.first?.name, "E\u{0301}COLE notes.txt", "case folding works on decomposed letters too")
    }

    func testComposedNamesMatchDecomposedQueries() async {
        let index = Fixture.index(["Docs/Résumé.pdf"])
        let found = await index.search("Re\u{0301}sume\u{0301}")
        XCTAssertEqual(found.first?.name, "Résumé.pdf")
    }

    func testHangulJamoMatchTheComposedSyllable() async {
        // 가 typed (U+AC00) finds a name stored as its jamo (U+1100 U+1161).
        let index = Fixture.index(["Docs/\u{1100}\u{1161} notes.txt"])
        let found = await index.search("\u{AC00}")
        XCTAssertEqual(found.first?.name, "\u{1100}\u{1161} notes.txt")
        XCTAssertEqual(NameFold.fold("\u{1100}\u{1161}"), NameFold.fold("\u{AC00}"))
    }

    func testFoldingAgainFixesNamesFoldedTheOldWay() {
        var storage = Fixture.storage(["plain.txt", "\u{1100}\u{1161}.txt"])
        // As an older build stored it: jamo left decomposed in the fold pool
        // (the last entry, so no other entry's bytes move).
        let i = storage.count - 1
        let start = Int(storage.foldStart[i])
        let old = Array("\u{1100}\u{1161}.txt".utf8)
        storage.folded.replaceSubrange(start..<(start + Int(storage.foldLength[i])), with: old)
        storage.foldLength[i] = UInt16(old.count)
        storage.refold()
        XCTAssertEqual(storage.foldStart.count, storage.count)
        let fold = Array(storage.folded[Int(storage.foldStart[i])..<(Int(storage.foldStart[i]) + Int(storage.foldLength[i]))])
        XCTAssertEqual(fold, NameFold.fold("\u{AC00}.txt"))
        XCTAssertEqual(storage.mask[i], NameFold.mask(fold))
        let plain = storage.parent.indices.first { storage.name($0) == "plain.txt" }!
        let plainFold = storage.folded[Int(storage.foldStart[plain])..<(Int(storage.foldStart[plain]) + Int(storage.foldLength[plain]))]
        XCTAssertEqual(Array(plainFold), Array("plain.txt".utf8))
    }

    // MARK: Adopting a snapshot

    private func candidate(_ origin: SnapshotAdoption.Origin, age: TimeInterval, complete: Bool = true, roots: [String] = ["/Users/me"]) -> SnapshotAdoption.Candidate {
        SnapshotAdoption.Candidate(
            url: URL(fileURLWithPath: "/tmp/\(origin.rawValue)"), origin: origin,
            modified: Date(timeIntervalSince1970: 1_800_000_000 - age), complete: complete, roots: roots
        )
    }

    func testTheServicesOwnSnapshotWins() {
        let chosen = SnapshotAdoption.choose(
            [candidate(.sight, age: 10), candidate(.own, age: 9_999), candidate(.nexus, age: 5)], roots: ["/Users/me"]
        )
        XCTAssertEqual(chosen?.origin, .own)
    }

    func testTheNewerAppSnapshotIsAdopted() {
        let roots = ["/Users/me"]
        XCTAssertEqual(SnapshotAdoption.choose([candidate(.sight, age: 100), candidate(.nexus, age: 50)], roots: roots)?.origin, .nexus)
        XCTAssertEqual(SnapshotAdoption.choose([candidate(.sight, age: 50), candidate(.nexus, age: 100)], roots: roots)?.origin, .sight)
    }

    func testAFinishedSnapshotBeatsANewerUnfinishedOne() {
        let chosen = SnapshotAdoption.choose(
            [candidate(.sight, age: 100), candidate(.nexus, age: 1, complete: false)], roots: ["/Users/me"]
        )
        XCTAssertEqual(chosen?.origin, .sight)
    }

    func testSnapshotsOfOtherFoldersAreLeftAlone() {
        let chosen = SnapshotAdoption.choose(
            [candidate(.own, age: 1, roots: ["/Users/other"]), candidate(.sight, age: 100)], roots: ["/Users/me"]
        )
        XCTAssertEqual(chosen?.origin, .sight)
        XCTAssertNil(SnapshotAdoption.choose([candidate(.nexus, age: 1, roots: ["/"])], roots: ["/Users/me"]))
    }

    func testAdoptsFromDiskAndPrunesWhatTheHomeIndexLeavesOut() async throws {
        let home = folder + "/home"
        try Fixture.make("Documents/Conj Flap/Lid Study - CONJ.docx", in: home)
        try Fixture.make("Library/Containers/com.example/conj-state.json", in: home)
        try Fixture.make("Library/CloudStorage/Drive/conj drive.docx", in: home)
        let locations = IndexLocations(home: home)
        // Nexus indexed all of ~/Library.
        let nexus = FileIndex(roots: [home])
        await nexus.build(savingTo: locations.nexusSnapshot)
        let candidates = SnapshotAdoption.candidates(locations)
        XCTAssertEqual(candidates.map(\.origin), [.nexus])
        let exclusions = IndexExclusions.home(home)
        let adopted = try XCTUnwrap(SnapshotAdoption.load(locations, exclusions: exclusions, order: .none))
        XCTAssertEqual(adopted.origin, .nexus)
        await adopted.index.prune(exclusions.paths)
        let names = await adopted.index.search("conj").map(\.name).sorted()
        XCTAssertEqual(names, ["Conj Flap", "Lid Study - CONJ.docx", "conj drive.docx"])
    }

    // MARK: Scope and narrowing

    func testScopedSearchKeepsToTheFolder() async {
        let index = Fixture.index(["Projects/Conj Flap/conj notes.txt", "Archive/conj old.txt", "conj top.txt"])
        let scoped = await index.search("conj", limit: 20, scope: ["/Index/Projects"], narrowing: nil)
        XCTAssertEqual(scoped.matches.map(\.name).sorted(), ["Conj Flap", "conj notes.txt"])
        let whole = await index.search("conj", limit: 20, scope: ["/Index"], narrowing: nil)
        XCTAssertEqual(whole.matches.count, 4, "the root as scope is the whole index")
        let outside = await index.search("conj", limit: 20, scope: ["/Elsewhere"], narrowing: nil)
        XCTAssertTrue(outside.matches.isEmpty)
    }

    func testEachCallerNarrowsOnItsOwn() async {
        let paths = (0..<300).map { "F\($0 % 5)/" + ["conj flap \($0).pdf", "lid study \($0).docx"][$0 % 2] }
        let index = Fixture.index(paths)
        var sight: SearchNarrowing? = nil
        var nexus: SearchNarrowing? = nil
        for (a, b) in [("c", "l"), ("co", "li"), ("con", "lid"), ("conj f", "lid s")] {
            let fromSight = await index.search(a, limit: 30, scope: nil, narrowing: sight)
            sight = fromSight.narrowing
            let fromNexus = await index.search(b, limit: 30, scope: nil, narrowing: nexus)
            nexus = fromNexus.narrowing
            let fresh = await Fixture.index(paths).search(a, limit: 30).map(\.path)
            XCTAssertEqual(fromSight.matches.map(\.path), fresh, a)
            let freshB = await Fixture.index(paths).search(b, limit: 30).map(\.path)
            XCTAssertEqual(fromNexus.matches.map(\.path), freshB, b)
        }
    }

    // MARK: Status

    func testStatusReportsTheIndex() async {
        let index = Fixture.index(["a/one.txt", "b/"])
        let status = await index.status()
        XCTAssertEqual(status.files, 4)
        XCTAssertFalse(status.building)
        XCTAssertEqual(status.roots, ["/Index"])
        XCTAssertEqual(IndexStatus(encoded: status.encoded()), status)
    }

    // MARK: Encoding

    func testMatchesRoundTrip() {
        let matches = [
            IndexMatch(path: "/Users/me/Documents/Conj Flap", name: "Conj Flap", isFolder: true, tier: .prefix, highlights: [0..<4]),
            IndexMatch(path: "/Users/me/Re\u{0301}sume\u{0301}.pdf", name: "Re\u{0301}sume\u{0301}.pdf", isFolder: false, tier: .fuzzy, highlights: [0..<2, 3..<8]),
            IndexMatch(path: "/x", name: "x", isFolder: false, tier: .exact, highlights: []),
        ]
        let data = MatchCodec.encode(matches)
        XCTAssertEqual(MatchCodec.decode(data), matches)
        XCTAssertEqual(MatchCodec.decode(MatchCodec.encode([])), [])
        XCTAssertNil(MatchCodec.decode(data.prefix(data.count - 3)), "a cut-off buffer is refused")
        XCTAssertNil(MatchCodec.decode(Data([9, 0, 0, 0])))
    }
}
