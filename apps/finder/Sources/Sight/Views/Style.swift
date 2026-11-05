import AppKit
import SwiftUI
import ThemeKit

/// Motion for the search window: critically damped springs, never on the
/// typing path, and short cross-fades instead when Reduce Motion is on (or
/// the theme sets UI_MOTION=reduced).
enum Motion {
    /// The theme's UI_MOTION, kept by ThemeStore.
    @MainActor static var themeReduced = false

    @MainActor static var reduced: Bool {
        themeReduced || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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

/// The type scale: system text styles, so tracking and leading come from
/// Apple's tables, with weight for emphasis rather than size.
enum Typo {
    /// The query: macOS Title 2 (17 pt).
    static let fieldNS = NSFont.preferredFont(forTextStyle: .title2)
    static let field = Font.title2
    /// Row titles, action names, preview text: Body (13 pt).
    static let row = Font.body
    /// Subtitles, accessories, chips, footer: Subheadline (11 pt).
    static let detail = Font.subheadline
    /// Section headings and the action panel title.
    static let heading = Font.subheadline.weight(.semibold)
    /// The scope chip in the field.
    static let scope = Font.callout.weight(.medium)
    /// Key caps.
    static let key = Font.subheadline.weight(.medium)
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

/// The window's surface: a behind-window material with the theme's
/// background laid over it, solid under Reduce Transparency.
struct PanelSurface: View {
    let theme: Theme
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(theme.background)
            } else {
                VisualEffectBackground(material: .popover, radius: radius)
                // The theme's colour, translucent, so the material still shows through.
                Color(theme.background).opacity(contrast == .increased ? 0.94 : 0.72)
            }
        }
    }
}

/// The edge of the window: a fine line, a defined one under Increase Contrast.
struct PanelBorder: View {
    let theme: Theme
    let radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var scale

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(contrast == .increased ? Color(theme.dim) : Color(theme.line).opacity(0.7),
                          lineWidth: contrast == .increased ? 1 : 1 / max(scale, 1))
    }
}

/// A hairline divider, one device pixel, softer over the material.
struct Hairline: View {
    let theme: Theme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(Color(theme.line).opacity(contrast == .increased ? 1 : 0.6))
            .frame(height: 1 / max(scale, 1))
    }
}

/// NSVisualEffectView blending behind the window, kept active while Sight
/// itself is not the active app, with continuous corners from its mask so
/// the blur and the window shadow follow the same shape.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let radius: CGFloat

    final class Coordinator {
        var radius: CGFloat?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        update(view, context.coordinator)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view, context.coordinator)
    }

    private func update(_ view: NSVisualEffectView, _ coordinator: Coordinator) {
        if view.material != material { view.material = material }
        // The mask is drawn again only when the radius changes (a theme's RADIUS_WINDOW).
        if coordinator.radius != radius {
            coordinator.radius = radius
            view.maskImage = Self.mask(radius: radius)
        }
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

/// The highlight behind a row: the theme's selection, inset with continuous
/// corners, darker while pressed; a faint wash on hover.
struct RowHighlight: View {
    let theme: Theme
    let selected: Bool
    let pressed: Bool
    let hovered: Bool
    var namespace: Namespace.ID?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.rowRadius(theme), style: .continuous)
        ZStack {
            if selected {
                highlight(shape)
            } else if pressed {
                shape.fill(Color(theme.text).opacity(0.12))
            } else if hovered {
                shape.fill(Color(theme.text).opacity(0.05))
            }
        }
        .padding(.horizontal, Space.inset)
    }

    @ViewBuilder private func highlight(_ shape: RoundedRectangle) -> some View {
        let fill = shape
            .fill(Color(theme.selection))
            .overlay(shape.fill(Color(theme.text).opacity(pressed ? 0.1 : 0)))
        if let namespace {
            fill.matchedGeometryEffect(id: "selection", in: namespace)
        } else {
            fill
        }
    }
}

/// A key cap: "⌘K", "↩".
struct Keycap: View {
    let keys: String
    let theme: Theme
    var color: Color?

    var body: some View {
        Text(keys)
            .font(Typo.key.monospacedDigit())
            .foregroundStyle(color ?? Color(theme.text))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(theme.text).opacity(0.08))
            )
            .fixedSize()
    }
}
