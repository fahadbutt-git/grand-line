import XCTest
import IndexKit
@testable import IndexService

/// The index service's pieces that run without launchd: the client's fallback
/// when no service answers, the service core's adoption of an app's snapshot,
/// the service name rules and the code requirements.
final class IndexServiceTests: XCTestCase {
    private var home = ""

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IndexServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        home = FolderWatcher.realPath(url.path)
        try make("Documents/Projects/Conj Flap/Lid Study - CONJ.docx")
        try make("Documents/Projects/Conj Flap/conj notes.txt")
        try make("Downloads/receipt.pdf")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    private func make(_ relative: String) throws {
        let url = URL(fileURLWithPath: home).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    /// A snapshot of the fixture home where `snapshot` says.
    private func saveSnapshot(_ snapshot: URL) async {
        let index = FileIndex(roots: [home], exclusions: IndexExclusions.home(home))
        await index.build(savingTo: snapshot)
    }

    private func absentService() -> String {
        "com.grandline.index.test-absent-\(UUID().uuidString)"
    }

    // MARK: Client fallback

    func testSearchFallsBackToTheSnapshotWhenTheServiceIsAbsent() async throws {
        await saveSnapshot(IndexLocations(home: home).snapshot)
        let starts = Counter()
        let client = SharedIndexClient(
            home: home, serviceName: absentService(), replyTimeout: 0.3, liveAfter: 60,
            starter: { starts.add() }
        )
        client.start()
        let started = Date()
        let found = await client.search("conj", limit: 10)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the search did not wait long on the absent service")
        XCTAssertEqual(found.map(\.name).sorted(), ["Conj Flap", "Lid Study - CONJ.docx", "conj notes.txt"])
        XCTAssertEqual(starts.value, 1, "the client asked for the service to be started, once")
        let again = await client.search("conj n", limit: 10)
        XCTAssertEqual(again.map(\.name), ["conj notes.txt"])
        XCTAssertEqual(starts.value, 1, "not again within a minute")
        let status = await client.status()
        XCTAssertEqual(status.source, .inApp)
        XCTAssertGreaterThan(status.files, 5)
        if case .down = client.currentState {} else { XCTFail("the client should think the service is down: \(client.currentState)") }
        client.stop()
    }

    func testFallbackAdoptsSightsSnapshotBeforeTheServiceMadeOne() async throws {
        await saveSnapshot(IndexLocations(home: home).sightSnapshot)
        let client = SharedIndexClient(home: home, serviceName: absentService(), replyTimeout: 0.3, liveAfter: 60, starter: {})
        let found = await client.search("receipt", limit: 5)
        XCTAssertEqual(found.first?.path, home + "/Downloads/receipt.pdf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: IndexLocations(home: home).snapshot.path), "the client never writes the service's snapshot")
    }

    func testWithoutAServiceTheCopyIsWalkedAndFollowed() async throws {
        let client = SharedIndexClient(home: home, serviceName: nil, starter: { XCTFail("there is no service to start") })
        client.start()
        var found: [IndexMatch] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
            found = await client.search("lid study", limit: 5)
        }
        XCTAssertEqual(found.first?.name, "Lid Study - CONJ.docx")
        try await Task.sleep(nanoseconds: 500_000_000)
        try make("Desktop/conj arrived.txt")
        var arrived: [IndexMatch] = []
        for _ in 0..<150 where arrived.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
            arrived = await client.search("conj arrived", limit: 5)
        }
        XCTAssertEqual(arrived.first?.path, home + "/Desktop/conj arrived.txt", "the copy follows FSEvents")
    }

    // MARK: The service core

    func testTheServiceAdoptsTheNewestAppSnapshotAndSavesItsOwn() async throws {
        let locations = IndexLocations(home: home)
        await saveSnapshot(locations.sightSnapshot)
        try make("Documents/after sight.txt")
        await saveSnapshot(locations.nexusSnapshot)
        // Make Sight's the older one.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -86_400)], ofItemAtPath: locations.sightSnapshot.path)
        let core = IndexServiceCore(locations: locations, saveEvery: 3_600, latency: 0.1)
        let index = await core.index()
        let found = await index.search("after sight")
        XCTAssertEqual(found.first?.name, "after sight.txt", "Nexus's newer snapshot was adopted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: locations.snapshot.path), "adopted, then saved as the service's own")
        let status = await core.status()
        XCTAssertEqual(status.source, .service)
        XCTAssertFalse(status.building, "a good snapshot is caught up, not walked again")
        XCTAssertTrue(core.serves(home: home))
        XCTAssertFalse(core.serves(home: home + "/Documents"))
        await index.stopWatching()
        core.stop()
    }

    func testTheServiceWalksWhenThereIsNoSnapshot() async throws {
        let core = IndexServiceCore(locations: IndexLocations(home: home), saveEvery: 3_600, latency: 0.1)
        let index = await core.index()
        var found: [IndexMatch] = []
        for _ in 0..<100 where found.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
            found = await index.search("receipt")
        }
        XCTAssertEqual(found.first?.name, "receipt.pdf")
        await index.stopWatching()
        core.stop()
    }

    func testMaintenanceRecordsTheFirstSweepDateAndSaves() async throws {
        let locations = IndexLocations(home: home)
        await saveSnapshot(locations.snapshot)
        let core = IndexServiceCore(locations: locations, saveEvery: 3_600, latency: 0.1)
        let index = await core.index()
        await index.noteOpened(home + "/Downloads/receipt.pdf")
        let dirty = await index.hasUnsavedChanges
        XCTAssertTrue(dirty)
        await core.maintain()
        let clean = await index.hasUnsavedChanges
        XCTAssertFalse(clean)
        XCTAssertNotNil(ServiceState.read(locations.state).lastSweep)
        await index.stopWatching()
        core.stop()
    }

    // MARK: Names and signatures

    func testServiceNames() {
        XCTAssertEqual(IndexServiceName.forClient([:]), "com.grandline.index")
        XCTAssertNil(IndexServiceName.forClient(["GRAND_LINE_JOURNEY": "1"]), "a journey never uses the Mac's own index")
        XCTAssertEqual(
            IndexServiceName.forClient(["GRAND_LINE_JOURNEY": "1", "GRAND_LINE_INDEX_SERVICE": "com.grandline.index.journey"]),
            "com.grandline.index.journey"
        )
        XCTAssertEqual(IndexServiceName.forClient(["GRAND_LINE_INDEX_SERVICE": "com.example.other"]), "com.grandline.index")
        XCTAssertEqual(IndexServiceName.forService(["GRAND_LINE_INDEX_SERVICE": "com.grandline.index.journey"]), "com.grandline.index.journey")
        XCTAssertEqual(IndexServiceName.forService([:]), "com.grandline.index")
    }

    func testCodeRequirements() {
        let ids = IndexServiceName.clients
        XCTAssertEqual(
            CodeSigning.requirement(allowing: ids, signer: CodeSigning.Signer(teamID: "ABCDE12345")),
            "anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\" and (identifier \"com.grandline.nexus\" or identifier \"com.grandline.sight\")"
        )
        XCTAssertEqual(
            CodeSigning.requirement(allowing: ["com.grandline.index"], signer: CodeSigning.Signer(leafSHA1: "0A1B")),
            "certificate leaf = H\"0A1B\" and (identifier \"com.grandline.index\")"
        )
        XCTAssertEqual(
            CodeSigning.requirement(allowing: ids, signer: CodeSigning.Signer(isAdHoc: true)),
            "(identifier \"com.grandline.nexus\" or identifier \"com.grandline.sight\")"
        )
        XCTAssertNil(CodeSigning.requirement(allowing: ids, signer: nil), "an unsigned development build sets none")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
