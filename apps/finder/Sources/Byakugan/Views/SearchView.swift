import LauncherKit
import SwiftUI
import ThemeKit

/// The window: search field, query chips, results, footer, and the preview pane
/// and action panel when they are open. Drawn at the top of a clear panel.
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var themes: ThemeStore

    var body: some View {
        let theme = themes.theme
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    FieldRow(model: model, theme: theme)
                    if !model.chips.isEmpty {
                        ChipsRow(chips: model.chips, theme: theme)
                    }
                    if !model.list.isEmpty {
                        ResultsList(model: model, theme: theme)
                            .frame(height: model.listHeight)
                    }
                    Spacer(minLength: 0)
                    FooterRow(model: model, theme: theme)
                }
                .frame(width: Metrics.width)
                // Room for the action panel, which sits above the footer.
                .frame(minHeight: model.actionPanel.map { ActionPanelView.height($0) + 46 } ?? 0, alignment: .top)
                if model.previewOpen, let row = model.list.selected, row.previewPath != nil || row.detail != nil {
                    Rectangle().fill(Color(theme.line)).frame(width: 1)
                    PreviewPane(row: row, theme: theme)
                        .frame(width: Metrics.preview, height: Metrics.previewHeight)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(theme.background))
            .overlay(alignment: .bottomTrailing) {
                if let panel = model.actionPanel {
                    ActionPanelView(state: panel, theme: theme)
                        .padding(.trailing, 10)
                        .padding(.bottom, 36)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).stroke(Color(theme.line), lineWidth: 1))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, theme.colorScheme)
    }
}

/// The magnifying glass and the field.
struct FieldRow: View {
    @ObservedObject var model: SearchModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.text.first.flatMap { Prefix(rawValue: String($0)) }?.symbol ?? "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.dim))
                .frame(width: 22)
            SearchField(model: model, theme: theme)
                .frame(height: 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(theme.line)).frame(height: 1) }
    }
}

/// QueryKit's reading of a `.` query: "Word or PDF", "changed in the last 30 days".
struct ChipsRow: View {
    let chips: [String]
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Text("Matching").foregroundStyle(Color(theme.dim))
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Color(theme.text))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(theme.chip)))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(theme.line)).frame(height: 1) }
    }
}

/// The selected row's shortcuts, or the pending confirmation, and the result count.
struct FooterRow: View {
    @ObservedObject var model: SearchModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 16) {
            ForEach(FooterHints.hints(for: model.list.selected, confirming: model.gate.pending), id: \.self) { hint in
                HStack(spacing: 4) {
                    Text(hint.keys).foregroundStyle(Color(theme.text))
                    Text(hint.label).lineLimit(1).truncationMode(.tail)
                }
                .foregroundStyle(Color(model.gate.isConfirming ? theme.highlight : theme.dim))
            }
            Spacer(minLength: 8)
            Text(model.status).lineLimit(1).fixedSize()
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color(theme.dim))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color(theme.line)).frame(height: 1) }
    }
}
