import AppKit
import SwiftUI

/// A borderless SF Symbol button of fixed size, so it never wraps or clips.
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? palette.accent : (isEnabled ? palette.text : palette.faint))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        // VoiceOver reads the tooltip, not the symbol's name.
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A shortcut drawn as a key: radius 5, theme chip colour, 11 pt.
struct KeyCap: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(palette.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 5).fill(palette.chip.opacity(0.6)))
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
            if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
            Text(title).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(isOn ? palette.selectionText : palette.dim)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? palette.selection : palette.field))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isOn ? palette.accent : palette.line, lineWidth: 0.5))
        .frame(maxWidth: 220)
        .fixedSize(horizontal: true, vertical: false)

        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// A vertical hairline that can be dragged to resize what is left of it.
struct ResizeHandle: View {
    let palette: Palette
    let onDrag: (Double) -> Void
    @Local private var start: Double? = nil
    let current: Double

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(width: 1)
            .overlay(Color.clear.frame(width: 7).contentShape(Rectangle()).onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let origin = start ?? current
                if start == nil { start = current }
                onDrag(origin + value.translation.width)
            }.onEnded { _ in start = nil }))
    }
}
