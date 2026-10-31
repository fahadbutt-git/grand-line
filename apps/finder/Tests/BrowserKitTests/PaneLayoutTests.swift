import XCTest
@testable import BrowserKit

/// R12 and R27: 1 to 4 panes, Tab, F5 and F6.
final class PaneLayoutTests: XCTestCase {
    func testCountsAreKeptBetweenOneAndFour() {
        XCTAssertEqual(PaneLayout(count: 0).count, 1)
        XCTAssertEqual(PaneLayout(count: 9).count, 4)
        var layout = PaneLayout(count: 3, focused: 2)
        layout.setCount(2)
        XCTAssertEqual(layout.focused, 1, "the focus stays on a pane that exists")
    }

    func testGrid() {
        XCTAssertEqual(PaneLayout(count: 1).grid.columns, 1)
        XCTAssertEqual(PaneLayout(count: 3).grid.columns, 3)
        XCTAssertEqual(PaneLayout(count: 4).grid.columns, 2)
        XCTAssertEqual(PaneLayout(count: 4).grid.rows, 2)
    }

    func testTabWrapsAround() {
        var layout = PaneLayout(count: 3)
        layout.focusNext()
        layout.focusNext()
        XCTAssertEqual(layout.focused, 2)
        layout.focusNext()
        XCTAssertEqual(layout.focused, 0)
        layout.focusPrevious()
        XCTAssertEqual(layout.focused, 2)
    }

    func testNextPaneIsTheTargetOfF5AndF6() {
        XCTAssertNil(PaneLayout(count: 1).nextPane)
        XCTAssertEqual(PaneLayout(count: 2, focused: 0).nextPane, 1)
        XCTAssertEqual(PaneLayout(count: 2, focused: 1).nextPane, 0)
        XCTAssertEqual(PaneLayout(count: 4, focused: 3).nextPane, 0)
    }

    func testAddAndClose() {
        var layout = PaneLayout(count: 3, focused: 1)
        XCTAssertEqual(layout.addPane(), 2)
        XCTAssertNil(layout.addPane(), "four is the most")
        XCTAssertTrue(layout.closePane(0))
        XCTAssertEqual(layout.count, 3)
        XCTAssertEqual(layout.focused, 1)
        var single = PaneLayout()
        XCTAssertFalse(single.closePane(0))
    }

    func testTransferPlans() {
        let downloads = home.appendingPathComponent("Downloads")
        XCTAssertEqual(PaneTransfer.plan(moving: false, from: .folder(downloads), to: .folder(documents)), .copy(to: documents))
        XCTAssertEqual(PaneTransfer.plan(moving: true, from: .folder(downloads), to: .folder(documents)), .move(to: documents))
        XCTAssertNil(PaneTransfer.plan(moving: true, from: .folder(documents), to: .folder(documents)))
        XCTAssertNil(PaneTransfer.plan(moving: false, from: .folder(documents), to: .recents))
        let zip = downloads.appendingPathComponent("Supplementary data.zip")
        XCTAssertEqual(PaneTransfer.plan(moving: true, from: .archive(zip, entry: ""), to: .folder(documents)), .extract(to: documents))
    }
}
