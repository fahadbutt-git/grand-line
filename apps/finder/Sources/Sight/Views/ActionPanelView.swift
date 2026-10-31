import LauncherKit
import SwiftUI
import ThemeKit

/// Command+K: every action of the selected row, with its shortcut. Long lists
/// (Open With) scroll, keeping the selected action in view.
struct ActionPanelView: View {
    let state: ActionPanelState
    let theme: Theme

    static let titleHeight: CGFloat = 24
    static let rowHeight: CGFloat = 26
    static let maxRows = 12

    /// The panel's height, so the window can make room for it.
    static func height(_ state: ActionPanelState) -> CGFloat {
        8 + titleHeight + rowHeight * CGFloat(min(state.actions.count, maxRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(theme.dim))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(height: Self.titleHeight)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(Array(state.actions.enumerated()), id: \.offset) { index, action in
                            row(action, index: index).id(index)
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
        .background(Color(theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Color(theme.line), lineWidth: 1))
    }

    private func row(_ action: LaunchAction, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.symbol)
                .font(.system(size: 12))
                .frame(width: 16)
            Text(action.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Return runs the selected action; the others show their own shortcut.
            Text(index == state.selected ? "↩" : action.shortcut?.label ?? "")
                .foregroundStyle(Color(theme.dim))
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(index == state.selected ? theme.selectionText : theme.text))
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(index == state.selected ? Color(theme.selection) : Color.clear)
    }
}
