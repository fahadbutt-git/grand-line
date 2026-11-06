import LauncherKit
import SwiftUI

/// The window: search field, query tokens, results, footer, and the preview
/// pane and action panel when they are open. Drawn at the top of a clear
/// panel on the system's own surface (Liquid Glass, or a behind-window
/// material before macOS 26), in the system's colours, so it looks like
/// Spotlight in Light and in Dark.
struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var presence: PanelPresence
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radius = Metrics.radius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let away = !presence.shown && !reduceMotion
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    FieldRow(model: model)
                    if !model.buffer.isEmpty {
                        BufferRow(model: model)
                    }
                    if !model.chips.isEmpty {
                        ChipsRow(chips: model.chips)
                    }
                    if !model.list.isEmpty {
                        ResultsList(model: model)
                            .frame(height: model.listHeight)
                    }
                    Spacer(minLength: 0)
                    FooterRow(model: model)
                }
                .frame(width: Metrics.width)
                // Room for the action panel, which sits above the footer.
                .frame(minHeight: model.actionPanel.map { ActionPanelView.height($0) + 46 } ?? 0, alignment: .top)
                if model.previewOpen, let row = model.list.selected, row.previewPath != nil || row.detail != nil {
                    Rectangle().fill(Palette.separator).frame(width: 1)
                    PreviewPane(row: row)
                        .frame(width: Metrics.preview, height: Metrics.previewHeight)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: away ? Motion.awayBlur : 0)
            .background(PanelSurface(radius: radius))
            .overlay(alignment: .bottomTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    if let panel = model.actionPanel {
                        ActionPanelView(state: panel, onChoose: { model.choosePanelAction(at: $0) })
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
            .overlay(PanelBorder(radius: radius))
            .scaleEffect(away ? Motion.awayScale : 1, anchor: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The magnifying glass and the field, as Spotlight draws them.
struct FieldRow: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(Typo.field.weight(.regular))
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            if let chip = model.scopeChip {
                // The prefix or keyword in use, as a search token: "Files", "Clipboard", "Commands".
                Text(chip)
                    .font(Typo.scope)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .fixedSize()
                    .accessibilityIdentifier("sight.scope")
            }
            SearchField(model: model)
                .frame(height: 28)
        }
        .padding(.horizontal, Space.column)
        .frame(height: Metrics.field)
        .overlay(alignment: .bottom) {
            if !model.list.isEmpty || !model.buffer.isEmpty || !model.chips.isEmpty { Hairline() }
        }
    }
}

/// A token in a row of them (the buffer, QueryKit's reading of a query).
private struct Token<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.fill.tertiary))
    }
}

/// The file buffer (Command+B): a token per file. Command+K acts on all of them.
struct BufferRow: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(model.buffer.chips) { chip in
                        Token {
                            HStack(spacing: 4) {
                                Text(chip.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 160)
                                Button {
                                    model.removeFromBuffer(chip.path)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(chip.name) from the buffer")
                            }
                        }
                        .help(chip.path)
                    }
                }
            }
            .scrollIndicators(.never)
            HStack(spacing: 4) {
                Keycap(keys: "⌘K")
                Text("acts on \(model.buffer.count == 1 ? "it" : "all \(model.buffer.count)")")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(Typo.detail.monospacedDigit())
        .padding(.horizontal, Space.column)
        .padding(.vertical, 7)
        .accessibilityIdentifier("sight.buffer")
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// QueryKit's reading of a `.` query: "Word or PDF", "changed in the last 30 days".
struct ChipsRow: View {
    let chips: [String]

    var body: some View {
        HStack(spacing: 6) {
            Text("Matching").foregroundStyle(.secondary)
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Token {
                    Text(chip)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .font(Typo.detail.monospacedDigit())
        .padding(.horizontal, Space.column)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// What Return does on the selected row, then its other keys (Open ↵, Show
/// in Finder ⌘↵, Actions ⌘K) as key caps, or the pending confirmation in the
/// system's warning colour. On the right, a message such as a script's progress.
struct FooterRow: View {
    @ObservedObject var model: SearchModel

    var body: some View {
        let hints = FooterHints.hints(for: model.list.selected, confirming: model.gate.pending, held: model.held)
        let confirming = model.gate.isConfirming
        HStack(spacing: 14) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in
                HStack(spacing: 5) {
                    Text(hint.label).lineLimit(1).truncationMode(.tail)
                    Keycap(keys: hint.keys, emphasis: confirming ? Color.orange : nil)
                }
                .foregroundStyle(confirming ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            Text(model.status).lineLimit(1).fixedSize()
        }
        .font(Typo.detail.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.column)
        .frame(height: Metrics.footer)
        .overlay(alignment: .top) { Hairline() }
    }
}
