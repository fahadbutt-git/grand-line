import AppKit
import SwiftUI

/// A borderless SF Symbol button of fixed size, so it never wraps or clips.
/// It darkens the moment it is pressed and shows a quiet fill on hover, as
/// toolbar buttons do.
struct SymbolButton: View {
    let symbol: String
    let help: String
    let palette: Palette
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(NexusType.toolbarSymbol)
                .imageScale(.medium)
                .foregroundStyle(isOn ? palette.accent : (isEnabled ? palette.text : palette.faint))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarButtonStyle(palette: palette, isOn: isOn))
        .disabled(!isEnabled)
        .help(help)
        // VoiceOver reads the tooltip, not the symbol's name.
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Press feedback on mouse-down (`isPressed`), a hover fill, and nothing
/// that waits: the fill follows the pointer at once.
struct ToolbarButtonStyle: ButtonStyle {
    let palette: Palette
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        ToolbarButtonBody(configuration: configuration, palette: palette, isOn: isOn)
    }
}

private struct ToolbarButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let palette: Palette
    let isOn: Bool
    @Local private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .onHover { hovering = $0 && isEnabled }
    }

    private var fill: Color {
        if configuration.isPressed { return palette.text.opacity(0.14) }
        if isOn { return palette.text.opacity(0.06) }
        return hovering ? palette.text.opacity(0.07) : .clear
    }
}

/// A text button in the accent colour that dims while pressed.
struct LinkButtonStyle: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.accent)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
    }
}

/// A shortcut drawn as a key: radius 5, theme chip colour, 11 pt.
struct KeyCap: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(NexusType.labelMediumNumbers)
            .foregroundStyle(palette.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.chip.opacity(0.6)))
    }
}

/// A chip: search scopes and query descriptions.
struct Chip: View {
    let title: String
    var symbol: String?
    let palette: Palette
    var isOn = false
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(NexusType.footnote) }
            Text(title).font(NexusType.label).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(isOn ? palette.selectionText : palette.dim)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(isOn ? palette.selection : palette.field))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(isOn ? palette.accent : palette.line, lineWidth: 0.5))
        .frame(maxWidth: 220)
        .fixedSize(horizontal: true, vertical: false)

        if let action {
            Button(action: action) { label }.buttonStyle(ChipButtonStyle())
        } else {
            label
        }
    }
}

/// Chips dim the moment they are pressed.
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A vertical hairline that can be dragged to resize what is left of it.
/// The drag is measured in window coordinates, so the divider follows the
/// pointer 1:1 even though it moves with the width it changes, and keeps the
/// offset from where it was grabbed. Past a limit it waits for the pointer
/// to come back to the limit before moving again.
struct ResizeHandle: View {
    let palette: Palette
    let onDrag: (Double) -> Void
    @Local private var start: Double? = nil
    @Local private var hovering = false
    let current: Double

    var body: some View {
        Hairline(palette: palette, axis: .vertical)
            .overlay(
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hovering = inside
                        updateCursor()
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { value in
                                let origin = start ?? current
                                if start == nil { start = current }
                                NSCursor.resizeLeftRight.set()
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    onDrag(origin + value.translation.width)
                                }
                            }
                            .onEnded { _ in
                                start = nil
                                updateCursor()
                            }
                    )
            )
            .accessibilityHidden(true)
    }

    private func updateCursor() {
        if hovering || start != nil {
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
