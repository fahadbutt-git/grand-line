import XCTest
@testable import DenDenKit

final class LayoutTests: XCTestCase {
    /// A 14-inch MacBook Pro at its default scale: 1512 x 982 points, with
    /// macOS reporting a 32 pt notch and the menu bar either side of it.
    let builtin = ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                             auxiliaryLeftWidth: 663, auxiliaryRightWidth: 664, menuBarHeight: 32, isBuiltin: true)
    /// An external display to the right, no notch.
    let external = ScreenInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBarHeight: 25)

    func testNotchSizeFromAuxiliaryAreas() {
        XCTAssertEqual(NotchGeometry.notchSize(of: builtin), CGSize(width: 185, height: 32))
        XCTAssertNil(NotchGeometry.notchSize(of: external))
        XCTAssertEqual(NotchGeometry.style(of: builtin), .notch)
        XCTAssertEqual(NotchGeometry.style(of: external), .pill)
    }

    func testImplausibleNotchFallsBack() {
        var odd = builtin
        odd.auxiliaryLeftWidth = 10
        odd.auxiliaryRightWidth = 10
        XCTAssertEqual(NotchGeometry.notchSize(of: odd), NotchMetrics.fallbackNotch)
    }

    func testCollapsedSizes() {
        XCTAssertEqual(NotchGeometry.collapsedSize(of: external), CGSize(width: NotchMetrics.pillWidth, height: 25))
        var hidden = external
        hidden.menuBarHeight = 0 // menu bar set to hide
        XCTAssertEqual(NotchGeometry.collapsedSize(of: hidden).height, 24)

        let plain = NotchGeometry.collapsedPanelSize(of: builtin, liveActivity: false)
        XCTAssertEqual(plain, CGSize(width: 185 + 2 * NotchMetrics.collapsedTopRadius, height: 32))
        let live = NotchGeometry.collapsedPanelSize(of: builtin, liveActivity: true)
        XCTAssertEqual(live.width - plain.width, 2 * NotchGeometry.wingWidth(collapsedHeight: 32))
        XCTAssertEqual(NotchGeometry.wingWidth(collapsedHeight: 32), 38)
    }

    func testCollapsedFrameSitsOverTheNotch() {
        let size = NotchGeometry.collapsedSize(of: builtin)
        let frame = NotchGeometry.topCentred(size, on: builtin)
        XCTAssertEqual(frame.maxY, builtin.frame.maxY)
        XCTAssertEqual(frame.minX, 663, accuracy: 1)
        XCTAssertEqual(frame.maxX, 1512 - 664, accuracy: 1)
    }

    func testExpandedHeightFollowsContent() {
        let m = NotchMetrics.self
        let three = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 3, userWidgets: 0))
        XCTAssertEqual(three.width, m.expandedWidth)
        XCTAssertEqual(three.height, 32 + 6 + m.sectionHeight + m.bottomPadding)

        let withChips = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 3, userWidgets: 4))
        XCTAssertEqual(withChips.height - three.height, m.sectionSpacing + 2 * m.chipHeight + m.chipSpacing)

        let issues = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 3, userWidgets: 4, showsIssues: true))
        XCTAssertEqual(issues.height - withChips.height, m.issuesHeight)

        let empty = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 0, userWidgets: 0))
        XCTAssertGreaterThan(empty.height, 32 + m.bottomPadding)
    }

    func testManyChipsStopGrowingAndScroll() {
        let four = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 3, userWidgets: 12))
        let fifty = NotchGeometry.expandedSize(of: builtin, content: PanelContent(sections: 3, userWidgets: 50))
        XCTAssertEqual(four, fifty)
        XCTAssertEqual(NotchGeometry.chipRows(for: 50), 17)
        XCTAssertEqual(NotchGeometry.chipRows(for: 0), 0)
        XCTAssertEqual(NotchGeometry.chipRows(for: 3), 1)
        XCTAssertEqual(NotchGeometry.chipRows(for: 4), 2)
    }

    func testExpandedFitsSmallScreens() {
        let small = ScreenInfo(id: 3, frame: CGRect(x: 0, y: 0, width: 600, height: 300), menuBarHeight: 24)
        let size = NotchGeometry.expandedSize(of: small, content: PanelContent(sections: 3, userWidgets: 12, showsIssues: true))
        XCTAssertLessThanOrEqual(size.width, 600 - 2 * NotchMetrics.screenMargin)
        XCTAssertLessThanOrEqual(size.height, 300 * 0.6)
    }

    func testPlacements() {
        func ids(_ p: [(screenID: UInt32, style: PanelStyle)]) -> [String] { p.map { "\($0.screenID):\($0.style.rawValue)" } }
        XCTAssertEqual(ids(NotchGeometry.placements(screens: [builtin, external], mainID: 1, external: .none)), ["1:notch"])
        XCTAssertEqual(ids(NotchGeometry.placements(screens: [builtin, external], mainID: 2, external: .pill)), ["1:notch", "2:pill"])
        // Lid closed: only the external display, which gets a pill.
        XCTAssertEqual(ids(NotchGeometry.placements(screens: [external], mainID: 2, external: .none)), ["2:pill"])
        // A Mac without a notch: its built-in display gets a pill.
        var flat = builtin
        flat.auxiliaryLeftWidth = nil
        flat.auxiliaryRightWidth = nil
        flat.safeAreaTop = 0
        XCTAssertEqual(ids(NotchGeometry.placements(screens: [flat], mainID: 1, external: .none)), ["1:pill"])
        XCTAssertEqual(ids(NotchGeometry.placements(screens: [], mainID: nil, external: .pill)), [])
    }
}
