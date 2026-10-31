import XCTest
@testable import QueryKit

/// `now` is 2026-10-31 12:00 UTC.
final class DateTests: XCTestCase {
    private func modified(_ query: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Bool {
        matches(query, [Key.modified: Fixture.date(year, month, day, hour)])
    }

    func testToday() {
        XCTAssertTrue(modified("modified:today", 2026, 10, 31, 1))
        XCTAssertTrue(modified("modified:today", 2026, 10, 31, 23))
        XCTAssertFalse(modified("modified:today", 2026, 10, 30, 23))
    }

    func testYesterday() {
        XCTAssertTrue(modified("modified:yesterday", 2026, 10, 30, 8))
        XCTAssertFalse(modified("modified:yesterday", 2026, 10, 31, 8))
        XCTAssertFalse(modified("modified:yesterday", 2026, 10, 29, 23))
    }

    func testWeekMonthYearAreRollingWindows() {
        XCTAssertTrue(modified("modified:week", 2026, 10, 25))
        XCTAssertFalse(modified("modified:week", 2026, 10, 23))
        XCTAssertTrue(modified("modified:month", 2026, 10, 2))
        XCTAssertFalse(modified("modified:month", 2026, 9, 30))
        XCTAssertTrue(modified("modified:year", 2025, 11, 2))
        XCTAssertFalse(modified("modified:year", 2025, 10, 30))
    }

    func testDaysAgoWithinAndOlder() {
        XCTAssertTrue(modified("modified:<30d", 2026, 10, 2))
        XCTAssertFalse(modified("modified:<30d", 2026, 9, 30))
        XCTAssertTrue(modified("modified:>30d", 2026, 9, 15))
        XCTAssertFalse(modified("modified:>30d", 2026, 10, 15))
        XCTAssertTrue(modified("modified:7d", 2026, 10, 30))
    }

    func testBareYearMonthDay() {
        XCTAssertTrue(modified("modified:2026", 2026, 1, 1))
        XCTAssertFalse(modified("modified:2026", 2025, 12, 31, 23))
        XCTAssertTrue(modified("modified:2026-05", 2026, 5, 31, 23))
        XCTAssertFalse(modified("modified:2026-05", 2026, 6, 1))
        XCTAssertTrue(modified("modified:2026-05-03", 2026, 5, 3, 18))
        XCTAssertFalse(modified("modified:2026-05-03", 2026, 5, 4))
    }

    func testComparisonsOnAbsoluteDates() {
        XCTAssertTrue(modified("modified:>2025", 2026, 1, 1))
        XCTAssertFalse(modified("modified:>2025", 2025, 12, 31))
        XCTAssertTrue(modified("modified:<2026", 2025, 12, 31))
        XCTAssertFalse(modified("modified:<2026", 2026, 1, 1))
        XCTAssertTrue(modified("modified:>=2026-05", 2026, 5, 1))
        XCTAssertFalse(modified("modified:>=2026-05", 2026, 4, 30))
        XCTAssertTrue(modified("modified:<=2026-05", 2026, 5, 31))
        XCTAssertFalse(modified("modified:<=2026-05", 2026, 6, 1))
        XCTAssertTrue(modified("modified:=2026-05-03", 2026, 5, 3))
    }

    func testRanges() {
        XCTAssertTrue(modified("modified:2026-01..2026-03", 2026, 3, 31, 23))
        XCTAssertFalse(modified("modified:2026-01..2026-03", 2026, 4, 1))
        XCTAssertFalse(modified("modified:2026-01..2026-03", 2025, 12, 31))
        XCTAssertTrue(modified("modified:7d..30d", 2026, 10, 10))
        XCTAssertFalse(modified("modified:7d..30d", 2026, 10, 28))
        XCTAssertFalse(modified("modified:7d..30d", 2026, 9, 20))
    }

    func testCreatedAndOpenedUseTheirAttributes() {
        XCTAssertTrue(matches("created:2026", [Key.created: Fixture.date(2026, 2, 1)]))
        XCTAssertFalse(matches("created:2026", [Key.modified: Fixture.date(2026, 2, 1)]))
        XCTAssertTrue(matches("opened:<7d", [Key.opened: Fixture.date(2026, 10, 29)]))
    }

    func testCalendarValidation() {
        XCTAssertEqual(root("modified:2024-02-29"), Node.term(.date(.modified, .equal(.day(year: 2024, month: 2, day: 29)))))
        XCTAssertNil(root("modified:2026-02-29"))
        XCTAssertNil(root("modified:2026-13"))
        XCTAssertNil(root("modified:26-01"))
    }
}
