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
        let again = await client.search("conj no", limit: 10)
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

    // MARK: Staying light

    func testTheCopyGoesAMinuteAfterItsLastUseOnceTheServiceAnswers() {
        let now = Date()
        XCTAssertEqual(SharedIndexClient.copyRelease(up: true, loaded: false, lastLocalUse: now, now: now), .keep)
        XCTAssertEqual(SharedIndexClient.copyRelease(up: false, loaded: true, lastLocalUse: .distantPast, now: now), .keep,
                       "while the service is out of reach the copy answers")
        XCTAssertEqual(SharedIndexClient.copyRelease(up: true, loaded: true, lastLocalUse: .distantPast, now: now), .now,
                       "a copy loaded for a slow start and never used goes at once")
        guard case .after(let wait) = SharedIndexClient.copyRelease(up: true, loaded: true, lastLocalUse: now.addingTimeInterval(-20), now: now) else {
            return XCTFail("a copy used 20 s ago is looked at again later")
        }
        XCTAssertEqual(wait, 40, accuracy: 0.01)
        XCTAssertEqual(SharedIndexClient.copyRelease(up: true, loaded: true, lastLocalUse: now.addingTimeInterval(-61), now: now), .now)
    }

    func testWarmingIsAtMostOnceAMinute() {
        var gate = WarmGate()
        let t = Date()
        XCTAssertTrue(gate.shouldWarm(at: t))
        XCTAssertFalse(gate.shouldWarm(at: t.addingTimeInterval(10)))
        XCTAssertFalse(gate.shouldWarm(at: t.addingTimeInterval(59)))
        XCTAssertTrue(gate.shouldWarm(at: t.addingTimeInterval(61)))
    }

    func testPeriodicWakeUpsMayComeAFifthLate() {
        XCTAssertEqual(IndexServiceCore.tolerance(for: 300), 60, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(IndexServiceCore.tolerance(for: 300), 300 * 0.1)
    }

    func testChangeNoticesWaitOnTheIndexInsteadOfPolling() async throws {
        let index = FileIndex(roots: [home], exclusions: IndexExclusions.home(home))
        await index.build()
        var iterator = index.generationChanges.makeAsyncIterator()
        // The build changed it: one element waits, however many steps it took.
        let first: Void? = await iterator.next()
        XCTAssertNotNil(first)
        try make("Documents/new note.txt")
        await index.apply([FolderChange(path: FolderWatcher.realPath(home + "/Documents"))])
        let second: Void? = await iterator.next()
        XCTAssertNotNil(second)
    }

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

    func testAdHocSigningIsSaidToProveOnlyTheUser() {
        XCTAssertEqual(CodeSigning.trust(CodeSigning.Signer(teamID: "ABCDE12345")), .certificate)
        XCTAssertEqual(CodeSigning.trust(CodeSigning.Signer(leafSHA1: "0A1B")), .certificate)
        XCTAssertEqual(CodeSigning.trust(CodeSigning.Signer(isAdHoc: true)), .sameUserOnly)
        XCTAssertEqual(CodeSigning.trust(nil), .sameUserOnly)
        XCTAssertNil(CodeSigning.trustWarning(CodeSigning.Signer(leafSHA1: "0A1B")))
        XCTAssertTrue(CodeSigning.trustWarning(CodeSigning.Signer(isAdHoc: true))?.contains("signed ad hoc") == true)
        XCTAssertTrue(CodeSigning.trustWarning(nil)?.contains("unsigned") == true)
    }

    func testOnlyThisUsersProcessesAreAccepted() {
        XCTAssertTrue(CodeSigning.acceptsPeer(uid: getuid()))
        XCTAssertTrue(CodeSigning.acceptsPeer(uid: 501, ownUID: 501))
        XCTAssertFalse(CodeSigning.acceptsPeer(uid: 502, ownUID: 501))
        XCTAssertFalse(CodeSigning.acceptsPeer(uid: 0, ownUID: 501), "not even root's")
    }

    func testAServiceProblemTravelsWithTheStatus() throws {
        var status = IndexStatus(files: 3, lastSync: nil, building: false, unreadable: [])
        status.problem = SharedIndexClient.signatureProblem
        let back = try XCTUnwrap(IndexStatus(encoded: status.encoded()))
        XCTAssertEqual(back.problem, SharedIndexClient.signatureProblem)
        // A status from a service built before the field still reads.
        let old = Data(#"{"files":1,"building":false,"unreadable":[],"complete":true,"roots":[],"source":"service"}"#.utf8)
        let decoded = try XCTUnwrap(IndexStatus(encoded: old))
        XCTAssertNil(decoded.problem)
        XCTAssertEqual(decoded.files, 1)
    }

    func testAnAdoptedSnapshotLosesWhatTheRulesLeaveOut() async throws {
        // Nexus indexed all of ~/Library, including a folder made after any
        // list of ~/Library's names would have been read.
        let locations = IndexLocations(home: home)
        try make("Library/Vendor/conj vendor.db")
        let nexus = FileIndex(roots: [home])
        await nexus.build(savingTo: locations.nexusSnapshot)
        let core = IndexServiceCore(locations: locations, saveEvery: 3_600, latency: 0.1)
        let index = await core.index()
        let names = await index.search("conj").map(\.name).sorted()
        XCTAssertEqual(names, ["Conj Flap", "Lid Study - CONJ.docx", "conj notes.txt"], "~/Library/Vendor is left out")
        await index.stopWatching()
        core.stop()
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
