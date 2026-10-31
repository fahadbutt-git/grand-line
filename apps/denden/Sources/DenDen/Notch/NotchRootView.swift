import AppKit
import SwiftUI
import DenDenKit

/// The whole panel: the closed notch (black, to match the camera housing,
/// or a themed pill on other displays) growing into the open panel, whose
/// colours all come from the theme.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var host: PanelHost
    @ObservedObject var theme: ThemeStore

    var body: some View {
        let open = model.isOpen
        let size = model.currentSize
        let top = open ? NotchMetrics.expandedTopRadius : NotchMetrics.collapsedTopRadius
        let bottom = open ? NotchMetrics.expandedBottomRadius : NotchMetrics.collapsedBottomRadius
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)

        ZStack(alignment: .top) {
            shape.fill(fill(open: open))
            if open || model.style == .pill {
                shape.stroke(theme.hairline, lineWidth: 0.5)
            }
            Group {
                if open {
                    ExpandedPanel(model: model, host: host, user: host.user)
                        .transition(.opacity.animation(.easeOut(duration: 0.14).delay(0.06)))
                } else if model.showsLiveActivity, let nowPlaying = host.nowPlaying {
                    LiveActivityView(model: nowPlaying, height: model.bandHeight, inset: top + 6)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { model.onTap?() }
        .contextMenu { PanelMenu(host: host) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(theme)
        .preferredColorScheme(theme.colorScheme)
    }

    private func fill(open: Bool) -> Color {
        if open { return theme.background }
        return model.style == .notch ? .black : theme.raised
    }
}

/// The right-click menu.
struct PanelMenu: View {
    let host: PanelHost
    var body: some View {
        Button("Reload widgets and theme") { host.reloadEverything() }
        Button("Open widgets folder") { host.user.openFolder() }
        Button("Open the log") { NSWorkspace.shared.open(Log.file) }
        Divider()
        Button("Quit Den Den") { NSApp.terminate(nil) }
    }
}

/// The open panel's contents.
struct ExpandedPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var host: PanelHost
    @ObservedObject var user: UserWidgets
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let inset = NotchMetrics.expandedTopRadius + NotchMetrics.sidePadding
        let sections = host.sections
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: model.bandHeight)
            Spacer().frame(height: 6)
            if !sections.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, widget in
                        if index > 0 {
                            Rectangle().fill(theme.hairline).frame(width: 0.5).padding(.horizontal, 12)
                        }
                        widget.makeView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(height: NotchMetrics.sectionHeight)
            }
            if !user.widgets.isEmpty {
                if !sections.isEmpty { Spacer().frame(height: NotchMetrics.sectionSpacing) }
                UserWidgetGrid(model: user)
                    .frame(height: gridHeight)
            }
            if sections.isEmpty && user.widgets.isEmpty {
                EmptyNote(text: "No widgets yet. Add one to ~/.config/grand-line/denden/widgets", action: user.openFolder)
                    .frame(height: 44, alignment: .center)
            }
            let issues = host.allIssues
            if let first = issues.first {
                IssuesLine(first: first, count: issues.count, all: issues) { NSWorkspace.shared.open(Log.file) }
                    .frame(height: NotchMetrics.issuesHeight, alignment: .bottomLeading)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset)
        .padding(.bottom, NotchMetrics.bottomPadding)
    }

    private var gridHeight: CGFloat {
        let rows = min(NotchGeometry.chipRows(for: user.widgets.count), NotchMetrics.maxVisibleChipRows)
        return CGFloat(rows) * NotchMetrics.chipHeight + CGFloat(max(0, rows - 1)) * NotchMetrics.chipSpacing
    }

    /// The top band: the date on the left, small widgets on the right, and
    /// nothing under the camera.
    private var header: some View {
        HStack(spacing: 0) {
            Text(Self.dateText(Date()))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: model.cameraWidth + 16)
            HStack(spacing: 10) {
                ForEach(Array(host.headerWidgets.enumerated()), id: \.offset) { _, widget in
                    widget.makeView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f.string(from: date)
    }
}

/// One line naming the first config problem; the tooltip lists them all.
private struct IssuesLine: View {
    @EnvironmentObject var theme: ThemeStore
    let first: ConfigIssue
    let count: Int
    let all: [ConfigIssue]
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                Text(count == 1 ? first.description : "\(count) problems. \(first.description)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(theme.muted)
        }
        .buttonStyle(.plain)
        .help(all.map(\.description).joined(separator: "\n"))
    }
}
