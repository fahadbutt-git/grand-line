import LauncherKit
import SwiftUI
import ThemeKit

/// Command+K: every action of the selected row, with its shortcut. Long lists
/// (Open With) scroll, keeping the selected action in view.
struct ActionPanelView: View {
    let state: ActionPanelState
    let theme: Theme
    var onChoose: (Int) -> Void = { _ in }

    /// "Copy name" → "copy-name", the row's accessibility identifier.
    static func slug(_ title: String) -> String {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.joined(separator: "-")
    }

    static let titleHeight: CGFloat = 24
    static let rowHeight: CGFloat = 26
    static let maxRows = 12

    /// The panel's height, so the window can make room for it.
    static func height(_ state: ActionPanelState) -> CGFloat {
        8 + titleHeight + rowHeight * CGFloat(min(state.actions.count, maxRows))
    }

    var body: some View {
        let radius = Metrics.panelRadius(theme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(state.title)
                .font(Typo.heading)
                .foregroundStyle(Color(theme.dim))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Space.column)
                .frame(height: Self.titleHeight)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(state.actions.enumerated()), id: \.offset) { index, action in
                            PressableRow(action: { onChoose(index) }) { pressed, hovered in
                                row(action, index: index)
                                    .background(RowHighlight(theme: theme, selected: index == state.selected,
                                                             pressed: pressed, hovered: hovered))
                            }
                            .id(index)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("action." + Self.slug(action.title))
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: Self.rowHeight * CGFloat(min(state.actions.count, Self.maxRows)))
                .onChange(of: state.selected) { _, index in proxy.scrollTo(index) }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 280)
        // A separate surface floating over the results: solid, so translucency never stacks on translucency.
        .background(shape.fill(Color(theme.panel)))
        .clipShape(shape)
        .overlay(PanelBorder(theme: theme, radius: radius))
        .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.16), radius: 14, x: 0, y: 6)
    }

    private func row(_ action: LaunchAction, index: Int) -> some View {
        let selected = index == state.selected
        return HStack(spacing: 8) {
            Image(systemName: action.symbol)
                .font(Typo.row)
                .imageScale(.small)
                .foregroundStyle(Color(selected ? theme.selectionText : theme.dim))
                .frame(width: 18)
            Text(action.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Return runs the selected action. The others show their own shortcut.
            if let keys = selected ? "↩" : action.shortcut?.label {
                Keycap(keys: keys, theme: theme, color: Color(theme.dim))
            }
        }
        .font(Typo.row)
        .foregroundStyle(Color(selected ? theme.selectionText : theme.text))
        .padding(.horizontal, Space.column)
        .frame(height: Self.rowHeight)
    }
}
