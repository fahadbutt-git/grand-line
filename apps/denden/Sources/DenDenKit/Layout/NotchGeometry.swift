import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What Den Den knows about one display, read from NSScreen by the app.
/// Coordinates are AppKit's: origin at the bottom left of the main display.
public struct ScreenInfo: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    /// `safeAreaInsets.top`: the notch's height, 0 on displays without one.
    public var safeAreaTop: CGFloat
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` widths: the menu bar
    /// either side of the notch. Both nil on displays without a notch.
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?
    /// `frame.maxY - visibleFrame.maxY`.
    public var menuBarHeight: CGFloat
    public var isBuiltin: Bool

    public init(id: UInt32, frame: CGRect, safeAreaTop: CGFloat = 0, auxiliaryLeftWidth: CGFloat? = nil,
                auxiliaryRightWidth: CGFloat? = nil, menuBarHeight: CGFloat = 24, isBuiltin: Bool = false) {
        self.id = id
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.menuBarHeight = menuBarHeight
        self.isBuiltin = isBuiltin
    }

    public var hasNotch: Bool { auxiliaryLeftWidth != nil && auxiliaryRightWidth != nil && safeAreaTop > 0 }
}

/// How the panel sits on a display: over the camera notch, or as a pill at
/// the top centre of a display without one.
public enum PanelStyle: String, Equatable, Sendable { case notch, pill }

/// What the open panel holds, which sets its height.
public struct PanelContent: Equatable, Sendable {
    /// Built-in widgets shown as columns (Now Playing, Today, Reminders).
    public var sections: Int
    /// User widgets, shown as chips three to a row.
    public var userWidgets: Int
    /// A line at the bottom naming config files with problems.
    public var showsIssues: Bool

    public init(sections: Int, userWidgets: Int, showsIssues: Bool = false) {
        self.sections = sections
        self.userWidgets = userWidgets
        self.showsIssues = showsIssues
    }
}

/// Every size the panel uses. Dense, on the package's 11/13/15 type scale.
public enum NotchMetrics {
    /// The notch of 14 and 16 inch MacBook Pros, for when macOS does not say.
    public static let fallbackNotch = CGSize(width: 185, height: 32)
    public static let pillWidth: CGFloat = 200
    public static let expandedWidth: CGFloat = 660
    public static let sidePadding: CGFloat = 16
    public static let bottomPadding: CGFloat = 14
    public static let sectionHeight: CGFloat = 120
    public static let sectionSpacing: CGFloat = 12
    public static let chipColumns = 3
    public static let chipHeight: CGFloat = 28
    public static let chipSpacing: CGFloat = 6
    /// Rows of chips shown before the list scrolls.
    public static let maxVisibleChipRows = 4
    public static let issuesHeight: CGFloat = 20
    /// Corner radii, as in Boring Notch and DynamicNotchKit: a small flare at
    /// the top, a larger round at the bottom.
    public static let collapsedTopRadius: CGFloat = 6
    public static let collapsedBottomRadius: CGFloat = 10
    public static let expandedTopRadius: CGFloat = 10
    public static let expandedBottomRadius: CGFloat = 18
    /// Keeps the open panel this far from the display's sides.
    public static let screenMargin: CGFloat = 8
}

public enum NotchGeometry {
    /// The camera housing's size, from the menu bar areas either side of it
    /// (the method DynamicNotchKit and Boring Notch use).
    public static func notchSize(of screen: ScreenInfo) -> CGSize? {
        guard screen.hasNotch, let left = screen.auxiliaryLeftWidth, let right = screen.auxiliaryRightWidth else { return nil }
        let width = screen.frame.width - left - right
        guard width > 40, width < screen.frame.width / 2 else {
            return CGSize(width: NotchMetrics.fallbackNotch.width, height: screen.safeAreaTop)
        }
        return CGSize(width: width, height: screen.safeAreaTop)
    }

    public static func style(of screen: ScreenInfo) -> PanelStyle {
        notchSize(of: screen) != nil ? .notch : .pill
    }

    /// The closed shape: the notch itself, or a pill the height of the menu bar.
    public static func collapsedSize(of screen: ScreenInfo) -> CGSize {
        if let notch = notchSize(of: screen) { return notch }
        let height = screen.menuBarHeight > 10 ? screen.menuBarHeight : 24
        return CGSize(width: NotchMetrics.pillWidth, height: height)
    }

    /// The width of each side wing while music plays: one notch height, a
    /// square for the artwork on the left and the playing bars on the right.
    public static func wingWidth(collapsedHeight h: CGFloat) -> CGFloat {
        h.rounded()
    }

    /// The artwork's side in the left wing: the same padding above, below
    /// and to its left.
    public static func wingArtworkSide(collapsedHeight h: CGFloat) -> CGFloat {
        max(10, (h - 2 * wingPadding(collapsedHeight: h)).rounded())
    }

    public static func wingPadding(collapsedHeight h: CGFloat) -> CGFloat {
        max(4, (h * 0.19).rounded())
    }

    /// The closed panel's size, wider when the live activity is showing.
    public static func collapsedSize(of screen: ScreenInfo, liveActivity: Bool) -> CGSize {
        var size = collapsedSize(of: screen)
        if liveActivity { size.width += 2 * wingWidth(collapsedHeight: size.height) }
        return size
    }

    /// The closed panel's window: the shape plus its two small top flares,
    /// so the body below the flares covers the camera housing exactly.
    public static func collapsedPanelSize(of screen: ScreenInfo, liveActivity: Bool) -> CGSize {
        var size = collapsedSize(of: screen, liveActivity: liveActivity)
        size.width += 2 * NotchMetrics.collapsedTopRadius
        return size
    }

    /// The open panel's size.
    public static func expandedSize(of screen: ScreenInfo, content: PanelContent) -> CGSize {
        let m = NotchMetrics.self
        let top = collapsedSize(of: screen).height
        var height = top + 6
        if content.sections > 0 { height += m.sectionHeight }
        let rows = chipRows(for: content.userWidgets)
        let visible = min(rows, m.maxVisibleChipRows)
        if visible > 0 {
            if content.sections > 0 { height += m.sectionSpacing }
            height += CGFloat(visible) * m.chipHeight + CGFloat(visible - 1) * m.chipSpacing
        }
        if content.showsIssues { height += m.issuesHeight }
        if content.sections == 0 && visible == 0 { height += 44 } // room for the "nothing to show" line
        height += m.bottomPadding
        let maxWidth = screen.frame.width - 2 * m.screenMargin
        let width = min(m.expandedWidth, maxWidth)
        let maxHeight = screen.frame.height * 0.6
        return CGSize(width: width.rounded(), height: min(height, maxHeight).rounded())
    }

    public static func chipRows(for count: Int) -> Int {
        count <= 0 ? 0 : (count + NotchMetrics.chipColumns - 1) / NotchMetrics.chipColumns
    }

    /// A size placed at the top centre of the display, in screen coordinates.
    public static func topCentred(_ size: CGSize, on screen: ScreenInfo) -> CGRect {
        CGRect(x: (screen.frame.midX - size.width / 2).rounded(),
               y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    /// Which displays get a panel, and in which style.
    ///
    /// - The built-in display always does (over its notch, or as a pill on a
    ///   Mac without one).
    /// - With `externalDisplays = pill`, every other display gets a pill.
    /// - With the lid closed (no built-in display), the main display gets a
    ///   pill, so Den Den never disappears.
    public static func placements(screens: [ScreenInfo], mainID: UInt32?,
                                  external: DenDenSettings.ExternalDisplays) -> [(screenID: UInt32, style: PanelStyle)] {
        var out: [(UInt32, PanelStyle)] = []
        let builtin = screens.filter(\.isBuiltin)
        for s in builtin { out.append((s.id, style(of: s))) }
        if external == .pill {
            for s in screens where !s.isBuiltin { out.append((s.id, .pill)) }
        } else if builtin.isEmpty, let target = screens.first(where: { $0.id == mainID }) ?? screens.first {
            out.append((target.id, .pill))
        }
        return out.map { (screenID: $0.0, style: $0.1) }
    }
}
