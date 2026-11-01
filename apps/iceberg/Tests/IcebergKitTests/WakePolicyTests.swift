import XCTest
@testable import IcebergKit

/// What keeps Iceberg from waking the Mac for nothing: timer tolerance,
/// when the playing bars move, the stream reader's waits, and asking for
/// one permission at a time.
final class WakePolicyTests: XCTestCase {
    func testTimersMayFireATenthLate() {
        XCTAssertEqual(WakePolicy.tolerance(forDelay: 60), 6, accuracy: 0.001)
        XCTAssertEqual(WakePolicy.tolerance(forDelay: 3600), 360, accuracy: 0.001)
        XCTAssertEqual(WakePolicy.tolerance(forDelay: 1), 0.5, accuracy: 0.001)
        for delay in [0.5, 2, 30, 300, 86_400] as [TimeInterval] {
            XCTAssertGreaterThanOrEqual(WakePolicy.tolerance(forDelay: delay), delay * 0.1)
        }
    }

    func testTheBarsMoveOnlyWhilePlayingAndNothingAsksThemToRest() {
        XCTAssertTrue(WakePolicy.barsMove(playing: true, reduceMotion: false, lowPower: false, displaysAsleep: false))
        XCTAssertFalse(WakePolicy.barsMove(playing: false, reduceMotion: false, lowPower: false, displaysAsleep: false))
        XCTAssertFalse(WakePolicy.barsMove(playing: true, reduceMotion: true, lowPower: false, displaysAsleep: false))
        XCTAssertFalse(WakePolicy.barsMove(playing: true, reduceMotion: false, lowPower: true, displaysAsleep: false))
        XCTAssertFalse(WakePolicy.barsMove(playing: true, reduceMotion: false, lowPower: false, displaysAsleep: true))
    }

    func testAQuietStreamIsNotLookedAtTenTimesASecond() {
        let now = Date()
        let idle = WakePolicy.streamPollTimeout(pending: false, lastDelivered: .distantPast, minimumInterval: 0.1, exited: false, now: now)
        XCTAssertEqual(idle, Int32(WakePolicy.idleWaitMilliseconds))
        XCTAssertGreaterThanOrEqual(idle, 1000)
        // A held-back line waits only until it may be shown.
        let held = WakePolicy.streamPollTimeout(pending: true, lastDelivered: now.addingTimeInterval(-0.04), minimumInterval: 0.1, exited: false, now: now)
        XCTAssertGreaterThanOrEqual(held, 55)
        XCTAssertLessThanOrEqual(held, 61)
        let due = WakePolicy.streamPollTimeout(pending: true, lastDelivered: now.addingTimeInterval(-1), minimumInterval: 0.1, exited: false, now: now)
        XCTAssertEqual(due, 1)
        // Once the command has exited, the last output is collected quickly.
        XCTAssertEqual(WakePolicy.streamPollTimeout(pending: false, lastDelivered: now, minimumInterval: 0.1, exited: true, now: now), 50)
    }

    func testOnePermissionPromptAtATime() {
        var pacing = PromptPacing()
        let t = Date()
        XCTAssertTrue(pacing.mayAsk(at: t))
        XCTAssertFalse(pacing.mayAsk(at: t), "a second prompt while the first is up")
        pacing.answered(at: t.addingTimeInterval(4))
        XCTAssertFalse(pacing.mayAsk(at: t.addingTimeInterval(5)), "right after the first was answered")
        XCTAssertTrue(pacing.mayAsk(at: t.addingTimeInterval(4 + PromptPacing.gap)))
    }

    func testAQuietStreamEndsPromptlyWhenStopped() {
        // The reader sleeps in poll() but stop() closes the pipes, which wakes it.
        let p = StreamProcess(command: "sleep 30")
        let ended = expectation(description: "ends")
        XCTAssertTrue(p.start(onLine: { _ in }, onExit: { _ in ended.fulfill() }))
        Thread.sleep(forTimeInterval: 0.2)
        let stopped = Date()
        p.stop()
        wait(for: [ended], timeout: 3)
        XCTAssertLessThan(Date().timeIntervalSince(stopped), 2)
    }
}
