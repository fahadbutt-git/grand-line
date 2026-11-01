import XCTest
@testable import IcebergKit

/// Today's calendar fetch runs off the main thread, one at a time: a burst
/// of change notices folds into one more fetch, never a pile of them.
final class FetchCoalescerTests: XCTestCase {
    func testOneAtATime() throws {
        var c = FetchCoalescer()
        let first = try XCTUnwrap(c.request())
        XCTAssertNil(c.request(), "one is running")
        XCTAssertNil(c.request())
        XCTAssertNil(c.request())
        let (use, next) = c.finished(first)
        XCTAssertTrue(use)
        let second = try XCTUnwrap(next, "the burst becomes exactly one more fetch")
        XCTAssertNotEqual(first, second)
        let (use2, next2) = c.finished(second)
        XCTAssertTrue(use2)
        XCTAssertNil(next2, "nothing was asked meanwhile")
        XCTAssertFalse(c.running)
    }

    func testCancelledFetchIsDropped() throws {
        var c = FetchCoalescer()
        let g = try XCTUnwrap(c.request())
        c.cancel()
        let (use, next) = c.finished(g)
        XCTAssertFalse(use, "the widget was turned off meanwhile")
        XCTAssertNil(next)
        XCTAssertNotNil(c.request(), "a new fetch can start")
    }
}
