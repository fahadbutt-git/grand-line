import AppKit
import SwiftUI

/// Motion for the search window: critically damped springs, never on the
/// typing path, and short cross-fades instead when Reduce Motion is on.
enum Motion {
    @MainActor static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The window materialising and going away: scale and blur together.
    static let present = Animation.spring(response: 0.26, dampingFraction: 1)
    /// The selection following the arrow keys: quick, so key repeat never lags.
    static let selection = Animation.spring(response: 0.18, dampingFraction: 1)
    /// The action panel opening from the corner it is anchored to.
    static let panel = Animation.spring(response: 0.22, dampingFraction: 1)
    /// What Reduce Motion uses in place of a spring.
    static let fadeDuration: TimeInterval = 0.12
    static let fade = Animation.easeOut(duration: fadeDuration)

    /// Window fades, in seconds: in with ease out, out with ease in (one path, mirrored).
    static let windowIn: TimeInterval = 0.14
    static let windowOut: TimeInterval = 0.12
    /// How far the window shrinks and blurs when away.
    static let awayScale: CGFloat = 0.97
    static let awayBlur: CGFloat = 3

    @MainActor static func selectionAnimation() -> Animation? { reduced ? nil : selection }
}

/// The type scale: system text styles, so tracking, leading and the user's
/// text size come from macOS, with weight for emphasis rather than size.
enum Typo {
    /// The query: macOS Title 1 (22 pt), as Spotlight's field.
    static let fieldNS = NSFont.preferredFont(forTextStyle: .title1)
    static let field = Font.title
    /// Row titles, action names, preview text: Body (13 pt).
    static let row = Font.body
    /// Subtitles, accessories, chips, footer: Subheadline (11 pt).
    static let detail = Font.subheadline
    /// Section headings and the action panel title.
    static let heading = Font.subheadline.weight(.semibold)
    /// The scope token in the field.
    static let scope = Font.body.weight(.medium)
    /// Key caps.
    static let key = Font.subheadline
}

/// Spacing on one 4 pt grid: every row, heading and the field start their
/// content on the same 16 pt column.
enum Space {
    /// From the window edge to the selection highlight.
    static let inset: CGFloat = 6
    /// From the highlight to the row's content.
    static let rowPadding: CGFloat = 10
    /// The content column: inset plus row padding.
    static let column: CGFloat = inset + rowPadding
}

/// Whether this Mac draws Liquid Glass (macOS 26 and later, built with its SDK).
enum Glass {
    static let available: Bool = {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }()
}

/// The system's own colours. Every one is dynamic: it follows Light and
/// Dark, the accent colour, the highlight colour and Increase Contrast as
/// they change, with nothing of Sight's own.
enum Palette {
    /// The selected row: the same accent fill a focused table or outline uses.
    static let selection = Color(nsColor: .selectedContentBackgroundColor)
    /// Text on the selected row.
    static let selectionText = Color(nsColor: .alternateSelectedControlTextColor)
    static let separator = Color(nsColor: .separatorColor)
}

/// The window's surface. On macOS 26 and later it is Liquid Glass, as
/// Spotlight is; before that a behind-window popover material. Both handle
/// Reduce Transparency and Increase Contrast themselves.
struct PanelSurface: NSViewRepresentable {
    enum Kind { case window, menu }
    var kind: Kind = .window
    let radius: CGFloat

    final class Coordinator {
        var radius: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            context.coordinator.radius = radius
            return glass
        }
        #endif
        let view = NSVisualEffectView()
        // The window: blends with what is behind it. The action panel: with
        // the window's own content, as a menu does.
        view.material = kind == .window ? .popover : .menu
        view.blendingMode = kind == .window ? .behindWindow : .withinWindow
        // Kept active while Sight is not the active app (its panel never activates it).
        view.state = .active
        view.isEmphasized = false
        update(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        update(view, context.coordinator)
    }

    private func update(_ view: NSView, _ coordinator: Coordinator) {
        guard coordinator.radius != radius else { return }
        coordinator.radius = radius
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.cornerRadius = radius
            return
        }
        #endif
        // Continuous corners from the mask, so the blur and the window shadow follow one shape.
        (view as? NSVisualEffectView)?.maskImage = Self.mask(radius: radius)
    }

    /// A stretchable continuous rounded rectangle: the corners are kept, the middle stretches.
    static func mask(radius: CGFloat) -> NSImage {
        // A continuous corner reaches about 1.53 radii along each edge.
        let edge = ceil(radius * 1.6) + 1
        let size = NSSize(width: edge * 2 + 1, height: edge * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
            NSColor.black.setFill()
            NSBezierPath(cgPath: path).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: edge, left: edge, bottom: edge, right: edge)
        image.resizingMode = .stretch
        return image
    }
}

/// The edge of the window before Liquid Glass: a fine light line, as on
/// Spotlight and menus, and a defined one under Increase Contrast. Glass
/// draws its own edge.
struct PanelBorder: View {
    let radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale

    var body: some View {
        if !Glass.available {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if contrast == .increased {
                shape.strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
            } else {
                // Dark mode lights the edge from inside, Light mode darkens it.
                shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.1),
                                   lineWidth: 1 / max(scale, 1))
            }
        }
    }
}

/// A divider, one device pixel, in the system separator colour.
struct Hairline: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 1 / max(scale, 1))
    }
}

/// A row that answers the pointer the way AppKit rows do: pressed on mouse
/// down, run on mouse up inside it, cancelled by dragging out, with hover.
struct PressableRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: (_ pressed: Bool, _ hovered: Bool) -> Label
    @Local private var pressed = false
    @Local private var hovered = false
    @Local private var size = CGSize.zero

    var body: some View {
        label(pressed, hovered)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onHover { inside in
                if hovered != inside { hovered = inside }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let inside = CGRect(origin: .zero, size: size).contains(value.location)
                        if pressed != inside { pressed = inside }
                    }
                    .onEnded { value in
                        pressed = false
                        if CGRect(origin: .zero, size: size).contains(value.location) { action() }
                    }
            )
    }
}

/// The highlight behind a row: the system's selection colour (the accent),
/// inset with continuous corners, a shade deeper while pressed; a faint fill
/// on hover, as a menu or a sidebar shows.
struct RowHighlight: View {
    let selected: Bool
    let pressed: Bool
    let hovered: Bool
    var namespace: Namespace.ID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
        ZStack {
            if selected {
                highlight(shape)
            } else if pressed {
                shape.fill(.fill.secondary)
            } else if hovered {
                shape.fill(.fill.quaternary)
            }
        }
        .padding(.horizontal, Space.inset)
    }

    @ViewBuilder private func highlight(_ shape: RoundedRectangle) -> some View {
        let fill = shape
            .fill(Palette.selection)
            .overlay(shape.fill(Color.black.opacity(pressed ? 0.12 : 0)))
        if let namespace {
            fill.matchedGeometryEffect(id: "selection", in: namespace)
        } else {
            fill
        }
    }
}

/// A key hint, as Spotlight and menus show one: the key symbols in a small
/// rounded cap, in the secondary label colour, white on a selected row.
struct Keycap: View {
    let keys: String
    var onSelection = false
    var emphasis: Color?

    var body: some View {
        Text(keys)
            .font(Typo.key.monospacedDigit())
            .foregroundStyle(emphasis ?? (onSelection ? Palette.selectionText.opacity(0.85) : Color.secondary))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onSelection ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(.fill.tertiary))
            )
            .fixedSize()
    }
}
