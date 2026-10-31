import XCTest
@testable import IcebergKit

final class RefreshSchedulerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func make() -> RefreshScheduler {
        let s = RefreshScheduler()
        s.setWidgets([(id: "fast", policy: .interval(10)), (id: "slow", policy: .interval(60)), (id: "open", policy: .onOpen)])
        return s
    }

    func testNothingRunsOrWakesWhileClosed() {
        let s = make()
        XCTAssertEqual(s.due(at: t0), [])
        XCTAssertNil(s.nextWakeup(after: t0))
        _ = s.panelOpened(at: t0)
        s.panelClosed()
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(1000)), [])
        XCTAssertNil(s.nextWakeup(after: t0.addingTimeInterval(1000)))
    }

    func testFirstOpenRunsEverything() {
        XCTAssertEqual(make().panelOpened(at: t0), ["fast", "slow", "open"])
    }

    func testIntervalsWhileOpen() {
        let s = make()
        _ = s.panelOpened(at: t0)
        XCTAssertEqual(s.nextWakeup(after: t0), t0.addingTimeInterval(10))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(5)), [])
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(10)), ["fast"])
        XCTAssertEqual(s.nextWakeup(after: t0.addingTimeInterval(10)), t0.addingTimeInterval(20))
        // A timer firing a little early still counts.
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(19.7)), ["fast"])
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(60)), ["fast", "slow"])
    }

    func testReopenRunsOnlyWhatIsStale() {
        let s = make()
        _ = s.panelOpened(at: t0)
        s.panelClosed()
        // 2 s later: nothing stale, and on-open is throttled.
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(2)), [])
        s.panelClosed()
        // 15 s later: the 10 s widget and the on-open widget.
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(15)), ["fast", "open"])
        s.panelClosed()
        XCTAssertEqual(s.panelOpened(at: t0.addingTimeInterval(70)), ["fast", "slow", "open"])
    }

    func testOnlyOnOpenWidgetsNeedNoTimer() {
        let s = RefreshScheduler()
        s.setWidgets([(id: "a", policy: .onOpen)])
        XCTAssertEqual(s.panelOpened(at: t0), ["a"])
        XCTAssertNil(s.nextWakeup(after: t0))
    }

    func testSetWidgetsKeepsHistoryForUnchangedWidgets() {
        let s = make()
        _ = s.panelOpened(at: t0)
        s.setWidgets([(id: "fast", policy: .interval(10)), (id: "slow", policy: .interval(30)), (id: "new", policy: .interval(10))])
        XCTAssertEqual(s.lastRun(of: "fast"), t0)
        XCTAssertNil(s.lastRun(of: "slow"))   // its policy changed
        XCTAssertEqual(s.widgetIDs, ["fast", "slow", "new"])
        XCTAssertEqual(s.nextWakeup(after: t0.addingTimeInterval(1)), t0.addingTimeInterval(1))
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(1)), ["slow", "new"])
    }

    func testInvalidate() {
        let s = make()
        _ = s.panelOpened(at: t0)
        s.invalidate("slow")
        XCTAssertEqual(s.due(at: t0.addingTimeInterval(1)), ["slow"])
    }

    func testDuplicateIDsAreIgnored() {
        let s = RefreshScheduler()
        s.setWidgets([(id: "a", policy: .onOpen), (id: "a", policy: .interval(10))])
        XCTAssertEqual(s.widgetIDs, ["a"])
    }
}
