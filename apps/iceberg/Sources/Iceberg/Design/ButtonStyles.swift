import SwiftUI
import IcebergKit

/// Buttons in the panel and the basket. The press shows on mouse-down
/// (dimmed, and an icon a little smaller), the pointer resting on one
/// lights a quiet plate behind it, and letting go settles back with a
/// critically damped spring. The panel never takes the keyboard, so these
/// have no focus ring; in Settings the standard controls keep theirs.
struct PanelButtonStyle: ButtonStyle {
    enum Kind {
        /// A symbol: a round plate on hover, smaller while pressed.
        case icon
        /// A word or a caption: dimmed while pressed, no plate.
        case text
        /// A chip or a row with its own background of this radius.
        case plate(radius: CGFloat)
    }

    var kind: Kind = .icon

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration, kind: kind)
    }
}

private struct PanelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PanelButtonStyle.Kind
    @EnvironmentObject var palette: SystemPalette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var display = DisplayOptions.shared
    @Local private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .opacity(isEnabled ? (pressed ? pressedOpacity : 1) : 0.4)
            .scaleEffect(pressed && isIcon && !display.reduceMotion ? MotionSpec.pressedScale : 1)
            .background { plate(pressed: pressed) }
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                withAnimation(Motion.hover) { hovering = inside }
            }
            // In on mouse-down at once, out with a spring.
            .animation(pressed ? .easeOut(duration: MotionSpec.pressDuration) : Motion.spring(MotionSpec.release),
                       value: pressed)
    }

    private var isIcon: Bool {
        if case .icon = kind { return true }
        return false
    }

    private var pressedOpacity: Double {
        if case .plate = kind { return 0.85 }
        return 0.55
    }

    @ViewBuilder
    private func plate(pressed: Bool) -> some View {
        let active = hovering && isEnabled
        switch kind {
        case .icon:
            Circle()
                .fill(palette.foreground.opacity(pressed ? 0.16 : (active ? 0.09 : 0)))
                .padding(-4)
        case .text:
            EmptyView()
        case .plate(let radius):
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape
                .fill(active || pressed ? palette.selection : palette.card)
                .overlay(shape.fill(palette.foreground.opacity(pressed ? 0.06 : 0)))
                .overlay {
                    if display.increaseContrast {
                        shape.strokeBorder(palette.strongLine, lineWidth: PixelGrid.hairline(scale: displayScale))
                    }
                }
        }
    }
}
