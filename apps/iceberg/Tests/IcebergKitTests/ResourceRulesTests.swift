import XCTest
@testable import IcebergKit

/// Battery and resource rules: updates only while shown (unless "always"),
/// a pause during sleep and Low Power Mode, backoff after failures, and a
/// cap on commands at once.
final class ResourceRulesTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    // MARK: Backoff

    func testBackoffDelays() {
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 0), 0)
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 1), 0, "one failure is a blip")
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 2), 10)
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 3), 20)
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 4), 40)
        XCTAssertEqual(FailureBackoff.delay(afterFailures: 50), FailureBackoff.maximum)
        XCTAssertEqual(FailureBackoff.streamDelay(afterFailures: 1), 2)
        XCTAssertEqual(FailureBackoff.streamDelay(afterFailures: 3), 8)
        XCTAssertEqual(FailureBackoff.streamDelay(afterFailures: 99), FailureBackoff.maximum)
    }

    func testBackoffClearsOnSuccess() {
        var b = FailureBackoff()
        b.record(success: false, at: t0)
        XCTAssertFalse(b.blocks(at: t0))
        b.record(success: false, at: t0)
        XCTAssertTrue(b.blocks(at: t0.addingTimeInterval(5)))
        XCTAssertFalse(b.blocks(at: t0.addingTimeInterval(10)))
        b.record(success: true, at: t0.addingTimeInterval(11))
        XCTAssertEqual(b.failures, 0)
        XCTAssertNil(b.notBefore)
    }

    func testFailingIntervalWidgetWaitsLonger() {
        let s = RefreshScheduler()
        s.setWidgets([RefreshScheduler.Spec(id: "status", policy: .interval(5))])
        XCTAssertEqual(s.panelOpened(at: t0), ["status"])
        s.record("status", success: false, at: t0)
        XCTAssertEqual(s.nextWakeup(after: t0), t0.addingTimeInterval(5), "one failure keeps the schedule")
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(5)), ["status"])
        s.record("status", success: false, at: t0.addingTimeInterval(5))
        // Two in a row: 10 s from the second failure, not 5.
        XCTAssertEqual(s.nextWakeup(after: t0.addingTimeInterval(5)), t0.addingTimeInterval(15))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(10)), [])
        XCTAssertEqual(s.backoffUntil("status", at: t0.addingTimeInterval(10)), t0.addingTimeInterval(15))
        XCTAssertTrue(s.isHeldBack("status", at: t0.addingTimeInterval(10)))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(15)), ["status"])
        s.record("status", success: true, at: t0.addingTimeInterval(15))
        XCTAssertNil(s.backoffUntil("status", at: t0.addingTimeInterval(15)))
    }

    func testFailingOnOpenWidgetSkipsOpensUntilItsWaitIsOver() {
        let s = RefreshScheduler()
        s.setWidgets([(id: "a", policy: .onOpen)])
        _ = s.panelOpened(at: t0)
        s.record("a", success: false, at: t0)
        s.record("a", success: false, at: t0)
        s.panelClosed()
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(5)), [])
        s.panelClosed()
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(11)), ["a"])
        s.resetBackoff("a")
        XCTAssertFalse(s.isHeldBack("a", at: t0.addingTimeInterval(11)))
    }

    // MARK: When shown, or always

    func testOnlyAlwaysWidgetsRunWhileClosed() {
        let s = RefreshScheduler()
        s.setWidgets([
            RefreshScheduler.Spec(id: "shown", policy: .interval(10)),
            RefreshScheduler.Spec(id: "always", policy: .interval(10), whileClosed: true),
        ])
        XCTAssertEqual(s.nextWakeup(after: t0), t0, "the always widget is due before any open")
        XCTAssertEqual(s.due(at: t0), ["always"])
        XCTAssertEqual(s.nextWakeup(after: t0), t0.addingTimeInterval(10))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(10)), ["always"])
        // Opening runs the one that waited, once.
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(12)), ["shown"])
        s.panelClosed()
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(40)), ["always"])
    }

    func testOnlyOnOpenWhenShownWidgetsNeedNoTimerWhileClosed() {
        let s = RefreshScheduler()
        s.setWidgets([RefreshScheduler.Spec(id: "a", policy: .onOpen, whileClosed: true)])
        XCTAssertNil(s.nextWakeup(after: t0))
        XCTAssertEqual(s.due(at: t0), [])
    }

    // MARK: Sleep and Low Power Mode

    func testPauseHoldsBackAllButAlwaysWidgets() {
        let s = RefreshScheduler()
        s.setWidgets([
            RefreshScheduler.Spec(id: "normal", policy: .interval(10)),
            RefreshScheduler.Spec(id: "open", policy: .onOpen),
            RefreshScheduler.Spec(id: "vital", policy: .interval(10), ignoresPause: true),
        ])
        s.isPaused = true
        XCTAssertEqual(s.panelOpened(at: t0), ["vital"])
        XCTAssertEqual(s.nextWakeup(after: t0), t0.addingTimeInterval(10))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(30)), ["vital"])
        XCTAssertTrue(s.isHeldBack("normal", at: t0))
        XCTAssertFalse(s.isHeldBack("vital", at: t0))
        // Low Power Mode goes off: what was missed runs once.
        s.isPaused = false
        XCTAssertEqual(s.resumed(at: t0.addingTimeInterval(31)), ["normal", "open"])
        XCTAssertEqual(s.resumed(at: t0.addingTimeInterval(32)), [])
    }

    func testResumeWhileClosedRunsNothingShownOnly() {
        let s = RefreshScheduler()
        s.setWidgets([RefreshScheduler.Spec(id: "a", policy: .interval(10)), RefreshScheduler.Spec(id: "b", policy: .onOpen)])
        s.isPaused = true
        s.isPaused = false
        XCTAssertEqual(s.resumed(at: t0), [])
    }

    func testGate() {
        XCTAssertTrue(ResourceGate().allows(always: false))
        XCTAssertNil(ResourceGate().reason)
        let low = ResourceGate(lowPower: true)
        XCTAssertFalse(low.allows(always: false))
        XCTAssertTrue(low.allows(always: true))
        XCTAssertEqual(low.reason, "Low Power Mode is on")
        XCTAssertEqual(ResourceGate(asleep: true, lowPower: true).reason, "The Mac is asleep")
    }

    // MARK: Signals and clicks

    func testMarkRunAndInvalidate() {
        let s = RefreshScheduler()
        s.setWidgets([(id: "sig", policy: .onOpen)])
        // A signal while closed: it runs on the next open, even within the throttle.
        _ = s.panelOpened(at: t0)
        s.panelClosed()
        s.invalidate("sig")
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(1)), ["sig"])
        s.markRun("sig", at: t0.addingTimeInterval(2))
        XCTAssertEqual(s.lastRun(of: "sig"), t0.addingTimeInterval(2))
    }

    func testEditingAWidgetKeepsItsBackoffOnlyWhileThePolicyStays() {
        let s = RefreshScheduler()
        s.setWidgets([(id: "a", policy: .interval(10))])
        _ = s.panelOpened(at: t0)
        s.record("a", success: false, at: t0)
        s.record("a", success: false, at: t0)
        s.setWidgets([(id: "a", policy: .interval(10))])
        XCTAssertNotNil(s.backoffUntil("a", at: t0))
        s.setWidgets([(id: "a", policy: .interval(20))])
        XCTAssertNil(s.backoffUntil("a", at: t0))
    }

    // MARK: Concurrency cap

    func testCapCanBeChangedAtRunTime() {
        let pool = CommandPool(maxConcurrent: 4)
        pool.maxConcurrent = 2
        XCTAssertEqual(pool.maxConcurrent, 2)
        for i in 0..<8 {
            pool.submit(id: "w\(i)", command: "sleep 0.15", timeout: 5) { _, _ in }
        }
        pool.waitUntilIdle()
        XCTAssertLessThanOrEqual(pool.peakConcurrency, 2)
        pool.maxConcurrent = 0
        XCTAssertEqual(pool.maxConcurrent, 1, "never less than one")
    }

    func testMaxConcurrentSetting() {
        XCTAssertEqual(IcebergSettings().maxConcurrent, 4)
        XCTAssertEqual(IcebergSettings.parse("max_concurrent = 2").0.maxConcurrent, 2)
        let (s, issues) = IcebergSettings.parse("max_concurrent = 64")
        XCTAssertEqual(s.maxConcurrent, 16)
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first?.line, 1)
    }
}
