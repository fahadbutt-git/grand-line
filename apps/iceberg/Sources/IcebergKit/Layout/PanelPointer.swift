import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

extension NotchGeometry {
    /// Below this the menu bar counts as hidden: a full-screen app's Space,
    /// or "Automatically hide and show the menu bar".
    public static let visibleMenuBarMinimum: CGFloat = 10

    /// True when the display's menu bar is hidden right now.
    public static func menuBarHidden(_ screen: ScreenInfo) -> Bool {
        screen.menuBarHeight < visibleMenuBarMinimum
    }

    /// Where the closed panel takes the pointer: exactly the shape, without
    /// its top flares or the live-activity wings. On a display with a notch
    /// that is the camera housing (no menu or status item can be there); on
    /// one without, the pill itself. Everything else of the closed window
    /// lets clicks through to the menu bar, the status items and the apps
    /// below.
    public static func hitZone(of screen: ScreenInfo, style: PanelStyle) -> CGRect {
        if style == .notch, let notch = notchSize(of: screen) {
            return topCentred(notch, on: screen)
        }
        return topCentred(collapsedSize(of: screen), on: screen)
    }

    /// Whether the closed shape is drawn. The pill sits on the menu bar, so
    /// it goes while the menu bar is hidden (a full-screen app, whose top
    /// edge it would otherwise cover for good); hovering the top centre still
    /// opens it.
    /// The notch always shows: it covers only the camera housing.
    public static func closedShapeVisible(on screen: ScreenInfo, style: PanelStyle) -> Bool {
        style == .notch || !menuBarHidden(screen)
    }

    /// Inclusive of the edges: a pointer pushed against the top of the
    /// display sits on the last row, which `CGRect.contains` leaves out.
    public static func contains(_ rect: CGRect, _ p: CGPoint) -> Bool {
        p.x >= rect.minX && p.x <= rect.maxX && p.y >= rect.minY && p.y <= rect.maxY
    }
}

/// When the open panel closes by itself, apart from the shortcut and the
/// close command.
///
/// - The pointer leaves it (after the close delay), as before.
/// - A click anywhere outside it.
/// - Escape.
/// - Opened from the keyboard, a URL or the menu bar item while the pointer
///   was elsewhere: there is no "leave" to wait for, so once the pointer
///   moves on (further than `moveAway` from where it was) while still
///   outside, that counts as leaving.
public struct PanelDismissal: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        /// Start the close delay.
        case armClose
        /// The pointer is inside: stop any pending close.
        case cancelClose
    }

    /// How far the pointer may drift, outside the panel, before a panel
    /// opened from the keyboard counts as left.
    public static let moveAway: CGFloat = 40

    private var anchor: CGPoint?
    private var wasInside = false
    private var armed = false

    public init() {}

    /// The panel opened. `pointer` is where the pointer is now; `inside`
    /// whether that is over the open panel.
    public mutating func opened(pointer: CGPoint, inside: Bool) {
        wasInside = inside
        armed = false
        anchor = inside ? nil : pointer
    }

    /// The pointer moved while the panel is open.
    public mutating func pointerMoved(to p: CGPoint, panel: CGRect) -> Action {
        let inside = NotchGeometry.contains(panel, p)
        defer { wasInside = inside }
        if inside {
            anchor = nil
            armed = false
            return wasInside ? .none : .cancelClose
        }
        if wasInside {
            armed = true
            return .armClose
        }
        if let a = anchor, hypot(p.x - a.x, p.y - a.y) > Self.moveAway, !armed {
            armed = true
            anchor = nil
            return .armClose
        }
        return .none
    }

    /// A mouse button went down at `p`: true closes the panel.
    public func closes(onClickAt p: CGPoint, panel: CGRect) -> Bool {
        !NotchGeometry.contains(panel, p)
    }
}
