import AppKit
import BrowserKit
import SwiftUI

/// Nexus's type scale. Every role maps to a macOS text style (body 13,
/// callout 12, subheadline 11, footnote 10), which carries Apple's tracking
/// and leading tables. The sidebar keeps its own larger size (R29).
enum NexusType {
    /// Sheet and window titles.
    static let title = Font.title3.weight(.semibold)
    /// Pane titles, popover titles, the selected file's name.
    static let headline = Font.body.weight(.semibold)
    /// File names, fields, the path bar, empty states.
    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    /// Secondary rows: task titles, list entries in popovers.
    static let callout = Font.callout
    static let calloutNumbers = Font.callout.monospacedDigit()
    /// Chips, status text, hints and section labels.
    static let label = Font.subheadline
    static let labelMedium = Font.subheadline.weight(.medium)
    static let labelNumbers = Font.subheadline.monospacedDigit()
    static let labelMediumNumbers = Font.subheadline.weight(.medium).monospacedDigit()
    /// Sidebar section headings, as Finder sets them.
    static let section = Font.subheadline.weight(.semibold)
    static let footnote = Font.footnote
    static let footnoteStrong = Font.footnote.weight(.semibold)
    /// Sidebar rows (R29: at least 14 pt).
    static let sidebar = Font.system(size: SidebarMetrics.fontSize)

    /// SF Symbols, all at regular weight so they read as one family.
    static let toolbarSymbol = Font.system(size: 15, weight: .regular)
    static let sidebarSymbol = Font.system(size: 15, weight: .regular)
    static let rowSymbol = Font.body
    static let smallSymbol = Font.subheadline
    static let tinySymbol = Font.footnote.weight(.semibold)
    static let emptySymbol = Font.system(size: 34, weight: .ultraLight)
}

/// The AppKit side of the type scale, for the list.
@MainActor
enum NexusAppKitType {
    static var body: NSFont { .preferredFont(forTextStyle: .body) }
    static var bodyNumbers: NSFont { .monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular) }
    static var label: NSFont { .preferredFont(forTextStyle: .subheadline) }
    static var labelMedium: NSFont { .systemFont(ofSize: label.pointSize, weight: .medium) }
    /// Row symbols: one size and weight in every column.
    static let rowSymbol = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular, scale: .medium)
}

/// Motion: critically damped springs that start from what is on screen, so
/// every change can be interrupted. Reduce Motion swaps them for a short
/// cross-fade.
enum Motion {
    /// Panels that show and hide (sidebar, preview, inspector, bars).
    static func panel(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 1)
    }

    /// Scrolling to keep up with a new column or a moved selection.
    static func follow(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)
    }

    /// Small state changes (hover, chips). Never on the selection path.
    static func quick(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 1)
    }

    /// A panel entering from `edge` leaves the same way; a fade alone with
    /// Reduce Motion.
    static func slide(_ edge: Edge, _ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// The system setting, for AppKit code outside SwiftUI's environment.
    @MainActor static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// The macOS sidebar material behind the sidebar, with vibrancy, following
/// the window's active state as Finder's does.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
        if view.blendingMode != blending { view.blendingMode = blending }
    }
}

/// The sidebar's background: the sidebar material tinted with the theme's
/// panel colour. Solid with Reduce Transparency, solid with an edge with
/// Increase Contrast.
struct SidebarBackground: View {
    let palette: Palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if reduceTransparency || contrast == .increased {
            palette.panel
        } else {
            ZStack {
                VisualEffect(material: .sidebar)
                palette.panel.opacity(0.72)
            }
        }
    }
}

/// A divider between parts of the window: a hairline that strengthens to the
/// theme's line colour with Increase Contrast.
struct Hairline: View {
    enum Axis { case horizontal, vertical }
    let palette: Palette
    var axis: Axis = .horizontal
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let color = contrast == .increased ? palette.line : palette.hairline
        switch axis {
        case .horizontal: Rectangle().fill(color).frame(height: 1)
        case .vertical: Rectangle().fill(color).frame(width: 1)
        }
    }
}

/// Where content meets the toolbar: a soft fade instead of a hard rule, as a
/// scroll edge effect. Increase Contrast keeps a defined line.
struct EdgeFade: View {
    let palette: Palette
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if contrast == .increased {
            Rectangle().fill(palette.line).frame(height: 1)
        } else {
            LinearGradient(colors: [palette.hairline, palette.hairline.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A row's selection and hover fill, in the theme's selection colour while
/// the window is active and the system's inactive grey when it is not.
struct SelectionFill: View {
    let palette: Palette
    let isSelected: Bool
    var isHovered = false
    var radius: CGFloat = 6
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
    }

    private var fill: Color {
        if isSelected {
            return activeState == .inactive ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : palette.selection
        }
        return isHovered ? palette.text.opacity(0.07) : Color.clear
    }
}

extension View {
    /// Runs `press` on mouse-down, as Finder selects, and `release` on
    /// mouse-up with whether the pointer moved (a drag) in between. A plain
    /// tap fires only on mouse-up, and next to a double-click it also waits
    /// out the double-click interval.
    func onPress(_ press: @escaping () -> Void, release: ((Bool) -> Void)? = nil) -> some View {
        modifier(PressGesture(press: press, release: release))
    }
}

private struct PressGesture: ViewModifier {
    let press: () -> Void
    let release: ((Bool) -> Void)?
    /// The press being tracked, by where it started. A press cut short by a
    /// drag session never ends, so a new start point always begins a new one.
    @Local private var start: CGPoint? = nil

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let isNew = start == nil || (value.translation == .zero && value.startLocation != start)
                    guard isNew else { return }
                    start = value.startLocation
                    press()
                }
                .onEnded { value in
                    start = nil
                    let moved = abs(value.translation.width) > 3 || abs(value.translation.height) > 3
                    release?(moved)
                }
        )
    }
}

/// Real file icons from Launch Services, cached by path, for the icon and
/// gallery views while a thumbnail loads and where there is none.
@MainActor
enum WorkspaceIcons {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 800
        return cache
    }()

    static func icon(for item: FileItem) -> NSImage? {
        guard !item.isInArchive else { return nil }
        let key = item.path as NSString
        if let known = cache.object(forKey: key) { return known }
        let image = NSWorkspace.shared.icon(forFile: item.path)
        cache.setObject(image, forKey: key)
        return image
    }
}
