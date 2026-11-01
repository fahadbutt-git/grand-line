import AppKit
import SwiftUI
import IcebergKit

/// The whole panel: the closed notch (black, to match the camera housing,
/// or a black pill on other displays) growing into the open panel, whose
/// colours all come from the theme.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var host: PanelHost
    @ObservedObject var theme: ThemeStore

    var body: some View {
        let open = model.isOpen
        let size = model.currentSize
        let pill = model.style == .pill
        let top = open ? NotchMetrics.expandedTopRadius : (pill ? 0 : NotchMetrics.collapsedTopRadius)
        let bottom = open ? NotchMetrics.expandedBottomRadius : (pill ? size.height / 2 : NotchMetrics.collapsedBottomRadius)
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)

        ZStack(alignment: .top) {
            surface(open: open)
            if open {
                shape.stroke(theme.line, lineWidth: 0.5)
            }
            Group {
                if open {
                    ExpandedPanel(model: model, host: host, user: host.user)
                        .transition(.opacity.animation(.easeOut(duration: 0.14).delay(0.06)))
                } else if model.showsLiveActivity, let nowPlaying = host.nowPlaying {
                    LiveActivityView(model: nowPlaying, height: model.bandHeight,
                                     inset: pill ? 0 : NotchMetrics.collapsedTopRadius,
                                     reduceMotion: !model.barsMove(playing: nowPlaying.isPlaying))
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

    /// Closed, all black like the camera housing (the pill too, so the
    /// wings look the same everywhere). Open, the theme's panel fades in over
    /// it, and only the piece under the camera stays black.
    private func surface(open: Bool) -> some View {
        ZStack(alignment: .top) {
            Color.black
            theme.panel.opacity(open ? 1 : 0)
            if model.style == .notch {
                NotchShape(topRadius: 0, bottomRadius: NotchMetrics.collapsedBottomRadius)
                    .fill(Color.black)
                    .frame(width: model.cameraWidth, height: model.bandHeight)
                    .opacity(open ? 1 : 0)
            }
        }
    }
}

/// The right-click menu.
struct PanelMenu: View {
    let host: PanelHost
    var body: some View {
        Button("Settings…") { host.openSettings?() }
        Divider()
        Button("Reload widgets and theme") { host.reloadEverything() }
        Button("Open widgets folder") { host.user.openFolder() }
        Button("Open the log") { NSWorkspace.shared.open(Log.file) }
        Divider()
        Button("Quit Iceberg") { NSApp.terminate(nil) }
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
                            Rectangle().fill(theme.line).frame(width: 0.5).padding(.horizontal, 12)
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
                EmptyNote(text: "Nothing is turned on. Choose what shows in Settings.", action: { host.openSettings?() })
                    .frame(height: 44, alignment: .center)
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
            Group {
                if host.showsDate {
                    Text(Self.dateText(Date()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                } else {
                    Color.clear
                }
            }
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
