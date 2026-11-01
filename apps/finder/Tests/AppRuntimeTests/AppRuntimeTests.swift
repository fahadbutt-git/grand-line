import XCTest
import AppRuntime

/// The pieces that keep the apps out of the way: when the hang watchdog
/// runs and what it writes, the crash-loop guard, the relaunch rule, and the
/// busy marker the unattended update reads.
final class AppRuntimeTests: XCTestCase {
    private var home = ""

    override func setUpWithError() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AppRuntimeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        home = url.path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    // MARK: Watchdog

    func testTheWatchdogRunsOnlyWhileTheAppIsInFrontOrJustUsed() {
        let now = Date()
        XCTAssertTrue(WatchWindow.isWatching(active: true, lastUse: nil, now: now))
        XCTAssertFalse(WatchWindow.isWatching(active: false, lastUse: nil, now: now))
        XCTAssertTrue(WatchWindow.isWatching(active: false, lastUse: now.addingTimeInterval(-5), now: now))
        XCTAssertFalse(WatchWindow.isWatching(active: false, lastUse: now.addingTimeInterval(-WatchWindow.afterUse - 1), now: now))
    }

    func testOnlyStallsOfAQuarterSecondOrMoreAreWritten() {
        XCTAssertNil(StallReport.line(delay: 0.1))
        XCTAssertEqual(StallReport.line(delay: 0.3), "main thread stalled 300 ms")
        let log = """
        2026-10-31T10:00:00Z main thread stalled 300 ms
        2026-10-31T10:00:02Z something else
        2026-10-31T10:00:04Z main thread stalled 1250 ms
        """
        XCTAssertEqual(StallReport.longest(in: log), 1250)
        XCTAssertEqual(StallReport.longest(in: ""), 0)
    }

    func testTheWatchdogStopsAfterUse() {
        let dog = HangWatchdog(log: AppLog(name: "test", home: home))
        XCTAssertFalse(dog.isRunning)
        dog.noteUse()
        XCTAssertTrue(dog.isRunning)
        dog.noteUse(at: Date().addingTimeInterval(-WatchWindow.afterUse - 5))
        XCTAssertFalse(dog.isRunning)
        dog.setActive(true)
        XCTAssertTrue(dog.isRunning)
        dog.setActive(false)
        XCTAssertFalse(dog.isRunning)
    }

    func testTheLogGoesToTheGrandLineLogsFolder() throws {
        let log = AppLog(name: "sight", home: home)
        log.write("main thread stalled 400 ms")
        log.flush()
        XCTAssertEqual(log.url.path, home + "/Library/Logs/grand-line/sight.log")
        let text = try String(contentsOf: log.url, encoding: .utf8)
        XCTAssertTrue(text.contains("main thread stalled 400 ms"))
    }

    // MARK: Crash loops

    func testACleanQuitIsNotACrash() {
        var record = RunRecord()
        let t = Date()
        XCTAssertEqual(record.launch(pid: 10, at: t), .run)
        record.quitCleanly()
        XCTAssertEqual(record.launch(pid: 11, at: t.addingTimeInterval(5)), .run)
        XCTAssertTrue(record.crashes.isEmpty)
    }

    func testThreeCrashesInTenMinutesStayDownAndSaySoOnce() {
        var record = RunRecord()
        let t = Date()
        XCTAssertEqual(record.launch(pid: 1, at: t), .run)
        XCTAssertEqual(record.launch(pid: 2, at: t.addingTimeInterval(60)), .runAfterCrash(started: t))
        XCTAssertEqual(record.launch(pid: 3, at: t.addingTimeInterval(120)), .runAfterCrash(started: t.addingTimeInterval(60)))
        XCTAssertEqual(record.launch(pid: 4, at: t.addingTimeInterval(180)), .stayDown(notify: true))
        // Staying down counts as a clean end, so nothing starts it again.
        XCTAssertEqual(RelaunchDecision.decide(record, alive: false), .nothing)
        // Opened again by hand: it runs, with the count started afresh.
        XCTAssertEqual(record.launch(pid: 5, at: t.addingTimeInterval(240)), .run)
        XCTAssertTrue(record.crashes.isEmpty)
    }

    func testCrashesFarApartDoNotAddUp() {
        var record = RunRecord()
        var t = Date()
        _ = record.launch(pid: 1, at: t)
        for pid in 2...6 {
            t = t.addingTimeInterval(RunRecord.loopWindow / 2 + 1)
            let decision = record.launch(pid: Int32(pid), at: t)
            XCTAssertNotEqual(decision, .stayDown(notify: true))
            XCTAssertNotEqual(decision, .stayDown(notify: false))
        }
    }

    func testOnlyACrashedAppIsRelaunched() {
        var running = RunRecord()
        _ = running.launch(pid: 1, at: Date())
        XCTAssertEqual(RelaunchDecision.decide(running, alive: true), .nothing)
        XCTAssertEqual(RelaunchDecision.decide(running, alive: false), .relaunch)
        var quit = running
        quit.quitCleanly()
        XCTAssertEqual(RelaunchDecision.decide(quit, alive: false), .nothing)
        XCTAssertEqual(RelaunchDecision.decide(nil, alive: false), .nothing)
    }

    func testTheGuardWritesItsRecordBesideTheStateFolder() {
        let log = AppLog(name: "guard", home: home)
        let guardian = CrashGuard(name: "sight", log: log, home: home)
        XCTAssertTrue(guardian.launch(displayName: "Sight"))
        XCTAssertEqual(guardian.url.path, home + "/.local/state/grand-line-runtime/sight.json")
        XCTAssertEqual(CrashGuard.read(guardian.url)?.cleanExit, false)
        guardian.quitCleanly()
        XCTAssertEqual(CrashGuard.read(guardian.url)?.cleanExit, true)
    }

    func testTheWatcherStartsACrashedAppInTheBackgroundOnly() {
        let log = AppLog(name: "watch", home: home)
        let sight = CrashGuard(name: "sight", log: log, home: home)
        _ = sight.launch(displayName: "Sight")
        // Pretend the run that wrote the record is gone.
        var record = CrashGuard.read(sight.url)!
        record.pid = 999_999
        CrashGuard.write(record, to: sight.url)
        let started = Started()
        let watcher = CrashWatcher(apps: [.init(name: "sight", bundleID: "com.grandline.sight"),
                                          .init(name: "iceberg", bundleID: "com.grandline.iceberg")],
                                   log: log, home: home, launcher: { started.add($0) })
        watcher.check()
        XCTAssertEqual(started.ids, ["com.grandline.sight"])
    }

    // MARK: Busy marker

    func testTheBusyMarkerIsThereWhileAnyReasonHolds() throws {
        let marker = BusyMarker(name: "nexus", home: home)
        marker.set("copy", busy: true)
        marker.set("move", busy: true)
        marker.set("copy", busy: false)
        try waitFor { FileManager.default.fileExists(atPath: marker.url.path) }
        marker.set("move", busy: false)
        try waitFor { !FileManager.default.fileExists(atPath: marker.url.path) }
    }

    private func waitFor(_ condition: () -> Bool) throws {
        let end = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > end { XCTFail("timed out"); return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}

private final class Started: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ id: String) { lock.lock(); list.append(id); lock.unlock() }
    var ids: [String] { lock.lock(); defer { lock.unlock() }; return list }
}
