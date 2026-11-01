import XCTest
@testable import IcebergKit

/// The closed panel takes the pointer only over its exact shape, and the
/// open one closes on a click outside, and when the pointer moves on after a
/// keyboard or URL open.
final class PanelPointerTests: XCTestCase {
    let builtin = ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                             auxiliaryLeftWidth: 663, auxiliaryRightWidth: 664, menuBarHeight: 32, isBuiltin: true)
    let external = ScreenInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBarHeight: 25)

    func testNotchHitZoneIsTheHousingOnly() {
        let zone = NotchGeometry.hitZone(of: builtin, style: .notch)
        XCTAssertEqual(zone.minX, 663, accuracy: 1)
        XCTAssertEqual(zone.maxX, 1512 - 664, accuracy: 1)
        XCTAssertEqual(zone.maxY, 982)
        XCTAssertEqual(zone.height, 32)
        // The wings and flares of the closed window lie outside it.
        let live = NotchGeometry.topCentred(NotchGeometry.collapsedPanelSize(of: builtin, liveActivity: true), on: builtin)
        XCTAssertGreaterThan(zone.minX, live.minX + NotchMetrics.collapsedTopRadius)
        XCTAssertFalse(NotchGeometry.contains(zone, CGPoint(x: live.minX + 2, y: 975)), "a click on the left wing goes through")
        XCTAssertTrue(NotchGeometry.contains(zone, CGPoint(x: zone.midX, y: 982)), "the top edge counts")
        XCTAssertFalse(NotchGeometry.contains(zone, CGPoint(x: zone.midX, y: 949)), "just below the notch is the app's")
    }

    func testPillHitZoneIsThePillWithoutFlares() {
        let zone = NotchGeometry.hitZone(of: external, style: .pill)
        XCTAssertEqual(zone.width, NotchMetrics.pillWidth)
        XCTAssertEqual(zone.height, 25)
        let window = NotchGeometry.topCentred(NotchGeometry.collapsedPanelSize(of: external, liveActivity: false), on: external)
        XCTAssertFalse(NotchGeometry.contains(zone, CGPoint(x: window.minX + 1, y: window.maxY - 1)))
    }

    /// A full-screen app hides the menu bar: the pill goes, the notch stays.
    func testPillHidesWithTheMenuBar() {
        var fullScreen = external
        fullScreen.menuBarHeight = 0
        XCTAssertTrue(NotchGeometry.closedShapeVisible(on: external, style: .pill))
        XCTAssertFalse(NotchGeometry.closedShapeVisible(on: fullScreen, style: .pill))
        var notchFull = builtin
        notchFull.menuBarHeight = 0
        XCTAssertTrue(NotchGeometry.closedShapeVisible(on: notchFull, style: .notch))
        XCTAssertTrue(NotchGeometry.menuBarHidden(fullScreen))
    }

    let panel = CGRect(x: 426, y: 760, width: 660, height: 222)

    func testClickOutsideCloses() {
        let d = PanelDismissal()
        XCTAssertTrue(d.closes(onClickAt: CGPoint(x: 100, y: 100), panel: panel))
        XCTAssertFalse(d.closes(onClickAt: CGPoint(x: panel.midX, y: panel.midY), panel: panel))
        XCTAssertFalse(d.closes(onClickAt: CGPoint(x: panel.minX, y: panel.maxY), panel: panel), "the edge is inside")
    }

    /// Opened by the shortcut with the pointer elsewhere: it stays while the
    /// pointer rests, and counts as left once the pointer moves on.
    func testKeyboardOpenClosesWhenThePointerMovesOn() {
        var d = PanelDismissal()
        let away = CGPoint(x: 700, y: 300)
        d.opened(pointer: away, inside: false)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: 710, y: 305), panel: panel), .none, "a small drift is not leaving")
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: 760, y: 330), panel: panel), .armClose)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: 800, y: 330), panel: panel), .none, "armed once")
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: panel.midX, y: panel.midY), panel: panel), .cancelClose, "came into it")
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: panel.midX, y: 100), panel: panel), .armClose, "and left again")
    }

    func testKeyboardOpenThenIntoThePanelStays() {
        var d = PanelDismissal()
        d.opened(pointer: CGPoint(x: 700, y: 700), inside: false)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: 700, y: 800), panel: panel), .cancelClose)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: 720, y: 820), panel: panel), .none)
    }

    func testHoverOpenClosesOnLeaving() {
        var d = PanelDismissal()
        d.opened(pointer: CGPoint(x: panel.midX, y: panel.maxY), inside: true)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: panel.midX, y: panel.midY), panel: panel), .none)
        XCTAssertEqual(d.pointerMoved(to: CGPoint(x: panel.midX, y: 200), panel: panel), .armClose)
    }
}
