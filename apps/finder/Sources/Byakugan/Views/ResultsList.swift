import LauncherKit
import SwiftUI
import ThemeKit

/// Section headers and rows; the selected row is kept in view.
struct ResultsList: View {
    @ObservedObject var model: SearchModel
    let theme: Theme

    var body: some View {
        let selectedID = model.list.selected?.id
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.list.groups) { group in
                        Text(group.section.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(theme.dim))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Metrics.header, alignment: .leading)
                            .padding(.horizontal, 14)
                        ForEach(group.rows) { row in
                            ResultRow(row: row, selected: row.id == selectedID, number: model.list.shortcutNumber(of: row.id), theme: theme)
                                .modifier(SettingRowAccessibility(row: row))
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.select(row)
                                    if let action = row.primary { model.run(action, on: row) }
                                }
                        }
                    }
                }
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
/// so the journey tests can find a row, press it and read what it did.
struct SettingRowAccessibility: ViewModifier {
    let row: LaunchResult

    @ViewBuilder func body(content: Content) -> some View {
        if row.providerID == SettingsActionsProvider.providerID {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(row.id)
                .accessibilityValue(row.accessory)
        } else {
            content
        }
    }
}

/// One dense row: icon, title with matched letters, where it is, a date or keys, and ⌘N.
struct ResultRow: View {
    let row: LaunchResult
    let selected: Bool
    let number: Int?
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            ResultIconView(icon: row.icon, theme: theme)
                .frame(width: 22, height: 22)
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(Color(selected ? theme.selectionText : theme.text))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text(row.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.dim))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 150, alignment: .leading)
            trailing
                .frame(minWidth: 70, alignment: .trailing)
            Text(number.map { "⌘\($0)" } ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(theme.faint))
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: Metrics.row)
        .background(selected ? Color(theme.selection) : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Color(theme.hairline)).frame(height: 1) }
    }

    @ViewBuilder private var trailing: some View {
        if !row.keys.isEmpty {
            HStack(spacing: 3) {
                ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(theme.chip)))
                }
            }
            .foregroundStyle(Color(theme.text))
            // Key caps keep their size; the title gives way.
            .fixedSize()
        } else {
            Text(row.accessory)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(theme.dim))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 70, alignment: .trailing)
        }
    }

    /// The title with the matched letters in the highlight colour.
    private var title: AttributedString {
        var text = AttributedString(row.title)
        for range in row.match.highlights {
            let ns = NSRange(location: range.lowerBound, length: range.count)
            if let found = Range(ns, in: text) {
                text[found].foregroundColor = Color(theme.highlight)
            }
        }
        return text
    }
}

/// An SF Symbol, an app's own icon, or a symbol character.
struct ResultIconView: View {
    let icon: ResultIcon
    let theme: Theme

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 14))
                .foregroundStyle(Color(theme.dim))
        case .app(let path):
            Image(nsImage: IconCache.icon(path))
                .resizable()
                .frame(width: 20, height: 20)
        case .glyph(let character):
            Text(character)
                .font(.system(size: 16))
                .foregroundStyle(Color(theme.text))
        }
    }
}
