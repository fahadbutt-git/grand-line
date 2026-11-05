import XCTest
@testable import LauncherKit

/// Actions in the app that was in front run when it is active, not after a fixed pause.
final class FrontAppWaitTests: XCTestCase {
    func testRunsAtOnceWhenTheAppIsAlreadyInFront() {
        XCTAssertEqual(FrontAppWait.plan(hasApp: true, isActive: true, isTerminated: false), .now)
    }

    func testRunsAtOnceWithNoAppOrAQuitApp() {
        XCTAssertEqual(FrontAppWait.plan(hasApp: false, isActive: false, isTerminated: false), .now)
        XCTAssertEqual(FrontAppWait.plan(hasApp: true, isActive: false, isTerminated: true), .now)
    }

    func testWaitsForActivationWithAShortLimit() {
        let plan = FrontAppWait.plan(hasApp: true, isActive: false, isTerminated: false)
        XCTAssertEqual(plan, .activation(limit: FrontAppWait.limit))
        XCTAssertLessThanOrEqual(FrontAppWait.limit, 0.5)
    }

    func testWorkRunsOnceWhicheverTriggerComesFirst() {
        var runs = 0
        let work = OnceWork { runs += 1 }
        work.run()
        work.run()
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(work.isDone)
    }

    func testCancelledWorkNeverRuns() {
        var runs = 0
        let work = OnceWork { runs += 1 }
        work.cancel()
        work.run()
        XCTAssertEqual(runs, 0)
    }
}
