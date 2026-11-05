import LauncherKit
import SwiftUI
import ThemeKit

/// The window: search field, query chips, results, footer, and the preview pane
/// and action panel when they are open. Drawn at the top of a clear panel, on a
/// behind-window material in the theme's colours.
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var themes: ThemeStore
    @ObservedObject var presence: PanelPresence
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let theme = themes.theme
        let radius = Metrics.radius(theme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let reduceMotion = systemReduceMotion || theme.tokens.motion == .reduced
        let away = !presence.shown && !reduceMotion
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    FieldRow(model: model, theme: theme)
                    if !model.buffer.isEmpty {
                        BufferRow(model: model, theme: theme)
                    }
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
                    Rectangle().fill(Color(theme.line).opacity(0.6)).frame(width: 1)
                    PreviewPane(row: row, theme: theme)
                        .frame(width: Metrics.preview, height: Metrics.previewHeight)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: away ? Motion.awayBlur : 0)
            .background(PanelSurface(theme: theme, radius: radius))
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    if let panel = model.actionPanel {
                        ActionPanelView(state: panel, theme: theme, onChoose: { model.choosePanelAction(at: $0) })
                            .transition(reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
                .padding(.trailing, 10)
                .padding(.bottom, Metrics.footer + 6)
                .animation(reduceMotion ? Motion.fade : Motion.panel, value: model.actionPanel != nil)
            }
            .clipShape(shape)
            .overlay(PanelBorder(theme: theme, radius: radius))
            .scaleEffect(away ? Motion.awayScale : 1, anchor: .top)
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
            Image(systemName: "magnifyingglass")
                .font(Typo.field)
                .imageScale(.medium)
                .foregroundStyle(Color(theme.dim))
                .frame(width: 22)
                .accessibilityHidden(true)
            if let chip = model.scopeChip {
                // The prefix or keyword in use: "Files", "Clipboard", "Commands".
                Text(chip)
                    .font(Typo.scope)
                    .foregroundStyle(Color(theme.text))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.rowRadius(theme), style: .continuous)
                            .fill(Color(theme.chip))
                    )
                    .fixedSize()
                    .accessibilityIdentifier("sight.scope")
            }
            SearchField(model: model, theme: theme)
                .frame(height: 22)
        }
        .padding(.horizontal, Space.column)
        .frame(height: Metrics.field)
        .overlay(alignment: .bottom) { Hairline(theme: theme) }
    }
}

/// The file buffer (Command+B): a chip per file. Command+K acts on all of them.
struct BufferRow: View {
    @ObservedObject var model: SearchModel
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(Color(theme.dim))
                .frame(width: 22)
                .accessibilityHidden(true)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.buffer.chips) { chip in
                        HStack(spacing: 4) {
                            Text(chip.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160)
                            Button {
                                model.removeFromBuffer(chip.path)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(Typo.detail.weight(.bold))
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(chip.name) from the buffer")
                        }
                        .foregroundStyle(Color(theme.text))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.rowRadius(theme), style: .continuous)
                                .fill(Color(theme.chip))
                        )
                        .help(chip.path)
                    }
                }
            }
            .scrollIndicators(.never)
            HStack(spacing: 4) {
                Keycap(keys: "⌘K", theme: theme)
                Text("acts on \(model.buffer.count == 1 ? "it" : "all \(model.buffer.count)")")
                    .foregroundStyle(Color(theme.dim))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(Typo.detail.monospacedDigit())
        .padding(.horizontal, Space.column)
        .padding(.vertical, 7)
        .accessibilityIdentifier("sight.buffer")
        .overlay(alignment: .bottom) { Hairline(theme: theme) }
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
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.rowRadius(theme), style: .continuous)
                            .fill(Color(theme.chip))
                    )
            }
            Spacer(minLength: 0)
        }
        .font(Typo.detail.monospacedDigit())
        .padding(.horizontal, Space.column)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Hairline(theme: theme) }
    }
}

/// What Return does on the selected row, then its other keys (Open ↵, Show
/// in Nexus ⌘↵, Actions ⌘K) as key caps, or the pending confirmation. On the
/// right, a message such as a script's progress.
struct FooterRow: View {
    @ObservedObject var model: SearchModel
    let theme: Theme

    var body: some View {
        let hints = FooterHints.hints(for: model.list.selected, confirming: model.gate.pending, held: model.held)
        let confirming = model.gate.isConfirming
        HStack(spacing: 14) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                HStack(spacing: 5) {
                    Text(hint.label).lineLimit(1).truncationMode(.tail)
                    Keycap(keys: hint.keys, theme: theme, color: confirming ? Color(theme.highlight) : nil)
                }
                .foregroundStyle(Color(confirming ? theme.highlight : theme.dim))
            }
            Spacer(minLength: 8)
            Text(model.status).lineLimit(1).fixedSize()
        }
        .font(Typo.detail.monospacedDigit())
        .foregroundStyle(Color(theme.dim))
        .padding(.horizontal, Space.column)
        .frame(height: Metrics.footer)
        .overlay(alignment: .top) { Hairline(theme: theme) }
    }
}
