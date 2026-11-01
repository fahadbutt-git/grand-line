import XCTest
import AppRuntime

/// A freeze that never ends still leaves a line: the second check writes
/// "main thread not answering" once, while the watched queue is stuck.
final class HangWatchdogFreezeTests: XCTestCase {
    var home: String!

    override func setUp() {
        home = NSTemporaryDirectory() + "hang-freeze-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: home)
    }

    private func text(_ log: AppLog) -> String {
        log.flush()
        return (try? String(contentsOf: log.url, encoding: .utf8)) ?? ""
    }

    func testFreezeLine() {
        XCTAssertEqual(FreezeReport.line(waited: 5), "main thread not answering for 5 s")
        XCTAssertTrue(FreezeReport.found(in: "2026-10-31T10:00:00Z main thread not answering for 5 s\n"))
        XCTAssertFalse(FreezeReport.found(in: "2026-10-31T10:00:00Z main thread stalled 300 ms\n"))
    }

    func testAFreezeIsWrittenOnceWhileItLasts() {
        let log = AppLog(name: "freeze", home: home)
        let stuck = DispatchQueue(label: "test.stuck")
        let release = DispatchSemaphore(value: 0)
        stuck.async { release.wait() }   // the "main thread" never answers
        let dog = HangWatchdog(log: log, target: stuck, freezeAfter: 0.3)
        dog.pingNow()
        dog.pingNow()   // still out: no second ping, no second line
        Thread.sleep(forTimeInterval: 0.8)
        let during = text(log)
        XCTAssertEqual(during.components(separatedBy: "main thread not answering").count - 1, 1, during)
        // It ends: the stall is written with its length as before.
        release.signal()
        Thread.sleep(forTimeInterval: 0.2)
        log.flush()
        Thread.sleep(forTimeInterval: 0.1)
        let after = text(log)
        XCTAssertTrue(after.contains("main thread stalled "), after)
        XCTAssertEqual(after.components(separatedBy: "main thread not answering").count - 1, 1)
    }

    func testAnAnsweredPingWritesNoFreeze() {
        let log = AppLog(name: "nofreeze", home: home)
        let free = DispatchQueue(label: "test.free")
        let dog = HangWatchdog(log: log, target: free, freezeAfter: 0.2)
        dog.pingNow()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(FreezeReport.found(in: text(log)))
    }

    func testStallLinesNameWhatTheAppWasDoing() {
        XCTAssertEqual(StallReport.line(delay: 1.985, phases: ["first show", "search"]),
                       "main thread stalled 1985 ms (during: first show, search)")
        XCTAssertEqual(StallReport.line(delay: 0.3, phases: [""]), "main thread stalled 300 ms")
        XCTAssertEqual(FreezeReport.line(waited: 5, phases: ["launch"]), "main thread not answering for 5 s (during: launch)")
        // The perf report and the journeys still read the length.
        XCTAssertEqual(StallReport.longest(in: "2026-10-31T10:00:00Z main thread stalled 1985 ms (during: search)\n"), 1985)
        XCTAssertTrue(FreezeReport.found(in: "x main thread not answering for 5 s (during: launch)\n"))
    }

    func testAStallIsWrittenWithThePhasesNamedWhileItLasted() {
        let log = AppLog(name: "phases", home: home)
        let stuck = DispatchQueue(label: "test.phases")
        let release = DispatchSemaphore(value: 0)
        let dog = HangWatchdog(log: log, target: stuck, freezeAfter: 5)
        dog.setPhase("first show")
        stuck.async { release.wait() }
        dog.pingNow()
        dog.setPhase("search")
        dog.setPhase("search")
        XCTAssertEqual(dog.currentPhase, "search")
        Thread.sleep(forTimeInterval: 0.4)
        release.signal()
        Thread.sleep(forTimeInterval: 0.2)
        let written = text(log)
        XCTAssertTrue(written.contains("(during: first show, search)"), written)
    }
}
