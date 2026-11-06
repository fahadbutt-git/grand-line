import LauncherKit
import SwiftUI

/// Section headers and rows; the selected row is kept in view. The list
/// itself never animates as the query changes, so typing is never held up.
/// Only the highlight glides when the arrow keys move it.
struct ResultsList: View {
    @ObservedObject var model: SearchModel
    @Namespace private var selection

    var body: some View {
        let selectedID = model.list.selected?.id
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.list.groups) { group in
                        Text(group.section.title)
                            .font(Typo.heading)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, minHeight: Metrics.header, alignment: .bottomLeading)
                            .padding(.horizontal, Space.column)
                        ForEach(group.rows) { row in
                            let selected = row.id == selectedID
                            PressableRow(action: {
                                model.select(row)
                                if let action = row.primary { model.run(action, on: row) }
                            }) { pressed, hovered in
                                ResultRow(row: row, selected: selected, number: model.list.shortcutNumber(of: row.id),
                                          held: selected ? model.held : .none)
                                    .background(RowHighlight(selected: selected, pressed: pressed,
                                                             hovered: hovered, namespace: selection))
                            }
                            .modifier(SettingRowAccessibility(row: row))
                            .id(row.id)
                        }
                    }
                }
                .padding(.vertical, Metrics.listInset)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}

/// Settings rows are one accessibility element each, named by their stable id
/// ("setting.darkmode") with the state as the value ("On", "Working", "Failed"),
/// so the journey tests can find a row, press it and read what it did. The
/// rows offered when nothing matches ("fallback:create-file") are named the same way.
struct SettingRowAccessibility: ViewModifier {
    let row: LaunchResult

    @ViewBuilder func body(content: Content) -> some View {
        if row.providerID == SettingsActionsProvider.providerID || row.providerID == FallbackCommandsProvider.providerID {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(row.id)
                .accessibilityValue(row.accessory)
        } else {
            content
        }
    }
}

/// One dense row: icon, title with matched letters, where it is, a date or
/// keys, and ⌘N. The title keeps its weight when selected, so nothing reflows
/// as the highlight moves.
struct ResultRow: View {
    let row: LaunchResult
    let selected: Bool
    let number: Int?
    /// Command or Option held on the selected row: the subtitle says what Return does then.
    var held: HeldModifier = .none

    var body: some View {
        HStack(spacing: 10) {
            ResultIconView(icon: row.icon, selected: selected)
                .frame(width: 24, height: 24)
            Text(title)
                .font(Typo.row)
                .foregroundStyle(selected ? AnyShapeStyle(Palette.selectionText) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text(ModifierPreview.subtitle(for: row, held: held) ?? row.subtitle)
                .font(Typo.detail)
                .foregroundStyle(secondaryStyle(emphasised: held != .none))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
            trailing
                .frame(minWidth: 70, alignment: .trailing)
            Text(number.map { "⌘\($0)" } ?? "")
                .font(Typo.detail.monospacedDigit())
                .foregroundStyle(selected ? AnyShapeStyle(Palette.selectionText.opacity(0.7)) : AnyShapeStyle(.tertiary))
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, Space.column)
        .frame(height: Metrics.row)
    }

    @ViewBuilder private var trailing: some View {
        if !row.keys.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                    Keycap(keys: key, onSelection: selected)
                }
            }
            // Key caps keep their size; the title gives way.
            .fixedSize()
        } else {
            Text(row.accessory)
                .font(Typo.detail.monospacedDigit())
                .foregroundStyle(secondaryStyle(emphasised: false))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 70, alignment: .trailing)
        }
    }

    /// Secondary text: the secondary label colour, or white on the selection.
    /// What Return does with a modifier held shows in the accent colour.
    private func secondaryStyle(emphasised: Bool) -> AnyShapeStyle {
        if selected { return AnyShapeStyle(Palette.selectionText.opacity(emphasised ? 1 : 0.8)) }
        return emphasised ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary)
    }

    /// The title with the matched letters in a heavier weight, so the match
    /// reads on the selection and off it, in any accent colour.
    private var title: AttributedString {
        var text = AttributedString(row.title)
        for range in row.match.highlights {
            let ns = NSRange(location: range.lowerBound, length: range.count)
            if let found = Range(ns, in: text) {
                text[found].font = Typo.row.weight(.semibold)
            }
        }
        return text
    }
}

/// An SF Symbol, an app's own icon, or a symbol character.
struct ResultIconView: View {
    let icon: ResultIcon
    var selected = false

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.title3)
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? AnyShapeStyle(Palette.selectionText) : AnyShapeStyle(Color.accentColor))
        case .app(let path):
            if let image = IconCache.cached(path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                // The same size and place as the icon that is on its way, so nothing moves when it lands.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.fill.quaternary)
                    .frame(width: 20, height: 20)
            }
        case .glyph(let character):
            Text(character)
                .font(.title3)
                .foregroundStyle(selected ? AnyShapeStyle(Palette.selectionText) : AnyShapeStyle(.primary))
        }
    }
}
