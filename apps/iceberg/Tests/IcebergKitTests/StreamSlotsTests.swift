import XCTest
@testable import IcebergKit

/// `max_concurrent` streams run at once; a waiting one takes a slot as soon
/// as one frees, not at the next open or close of the panel.
final class StreamSlotsTests: XCTestCase {
    let five = ["a", "b", "c", "d", "e"]

    func testExtraStreamsWait() {
        let p = StreamSlots.plan(wanted: five, running: [], restarting: [], max: 4)
        XCTAssertEqual(p.start, ["a", "b", "c", "d"])
        XCTAssertEqual(p.waiting, ["e"])
    }

    /// One of four ends by itself: the waiting fifth starts, the one that
    /// ended does not (it ended cleanly; nothing asked for it again).
    func testAFreedSlotGoesToTheWaitingStream() {
        let p = StreamSlots.plan(wanted: five, running: ["a", "b", "d"], restarting: [], max: 4, eligible: ["e"])
        XCTAssertEqual(p.start, ["e"])
        XCTAssertEqual(p.waiting, [])
    }

    func testRestartingStreamsAreLeftToTheirTimer() {
        let p = StreamSlots.plan(wanted: five, running: ["a", "b"], restarting: ["c"], max: 4)
        XCTAssertEqual(p.start, ["d", "e"])
        XCTAssertEqual(p.waiting, [])
        let full = StreamSlots.plan(wanted: five, running: ["a", "b", "d", "e"], restarting: ["c"], max: 4)
        XCTAssertEqual(full.start, [])
        XCTAssertEqual(full.waiting, [], "a stream waiting to restart is not shown as waiting for a slot")
    }

    func testNoSlotNoStart() {
        let p = StreamSlots.plan(wanted: five, running: ["a", "b", "c", "d"], restarting: [], max: 4, eligible: ["e"])
        XCTAssertEqual(p.start, [])
        XCTAssertEqual(p.waiting, ["e"])
    }
}
