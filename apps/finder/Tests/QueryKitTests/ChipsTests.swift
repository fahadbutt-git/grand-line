import XCTest
@testable import QueryKit

final class ChipsTests: XCTestCase {
    func testTermsAndBooleans() {
        XCTAssertEqual(chips("endo* \"anterior chamber\" -draft"), ["endo\u{2026}", "\"anterior chamber\"", "not draft"])
        XCTAssertEqual(chips("a b OR c"), ["(a and b) or c"])
        XCTAssertEqual(chips("-(a OR b)"), ["not (a or b)"])
        XCTAssertEqual(chips("@weekly"), ["@weekly"])
    }

    func testFilterChips() {
        XCTAssertEqual(chips("name:endo* name:protocol"), ["name starts with endo", "name has protocol"])
        XCTAssertEqual(chips("ext:docx tag:Urgent author:Smith from:trinetx.com"), [".docx", "tagged Urgent", "by Smith", "from trinetx.com"])
        XCTAssertEqual(chips("kind:doc,pdf kind:sheet"), ["Word or PDF", "spreadsheet"])
        XCTAssertEqual(chips("drive: local: in:Downloads"), ["in Google Drive", "on this Mac", "in Downloads"])
    }

    func testDateChips() {
        XCTAssertEqual(chips("modified:<30d"), ["changed in the last 30 days"])
        XCTAssertEqual(chips("modified:week"), ["changed in the last 7 days"])
        XCTAssertEqual(chips("modified:1d"), ["changed in the last day"])
        XCTAssertEqual(chips("modified:>30d"), ["changed more than 30 days ago"])
        XCTAssertEqual(chips("created:today"), ["created today"])
        XCTAssertEqual(chips("created:2026"), ["created in 2026"])
        XCTAssertEqual(chips("created:<2026"), ["created before 2026"])
        XCTAssertEqual(chips("created:>=2026-05"), ["created in or after May 2026"])
        XCTAssertEqual(chips("opened:2026-05-03"), ["opened on May 3, 2026"])
        XCTAssertEqual(chips("modified:2026-01..2026-03"), ["changed between January 2026 and March 2026"])
    }

    func testSizePagesAndSortChips() {
        XCTAssertEqual(chips("size:>5mb"), ["larger than 5 MB"])
        XCTAssertEqual(chips("size:<=1.5gb"), ["at most 1.5 GB"])
        XCTAssertEqual(chips("size:1kb..2mb"), ["between 1 KB and 2 MB"])
        XCTAssertEqual(chips("size:=500b"), ["exactly 500 bytes"])
        XCTAssertEqual(chips("pages:<15 pages:10..20 pages:1"), ["fewer than 15 pages", "10 to 20 pages", "1 page"])
        XCTAssertEqual(chips("sort:modified"), ["sorted by date modified"])
    }
}
