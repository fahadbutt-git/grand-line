import BrowserKit
import SwiftUI

/// The window: sidebar, toolbar, panes, preview and inspector, footer.
struct BrowserRootView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var services: Services
    @ObservedObject var theme: ThemeStore

    var body: some View {
        let palette = theme.palette
        HStack(spacing: 0) {
            if model.showSidebar {
                SidebarView(model: model, sidebar: services.sidebar, palette: palette)
                    .frame(width: model.sidebarWidth)
                ResizeHandle(palette: palette, onDrag: { model.sidebarWidth = SidebarMetrics.clamp($0) }, current: model.sidebarWidth)
            }
            VStack(spacing: 0) {
                if model.showToolbar {
                    ToolbarView(model: model, palette: palette)
                    Rectangle().fill(palette.hairline).frame(height: 1)
                } else {
                    Color.clear.frame(height: 28)
                }
                HStack(spacing: 0) {
                    PaneArea(model: model, palette: palette)
                        .popover(isPresented: $model.showViewOptions, arrowEdge: .top) {
                            ViewOptionsView(model: model, pane: model.focused, palette: palette)
                        }
                    if model.showPreview {
                        Rectangle().fill(palette.hairline).frame(width: 1)
                        PreviewPane(pane: model.focused, palette: palette).frame(width: 320)
                    }
                    if model.showInspector {
                        Rectangle().fill(palette.hairline).frame(width: 1)
                        InspectorView(model: model, pane: model.focused, palette: palette).frame(width: 280)
                    }
                }
                if model.showStatusBar {
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    FooterView(model: model, pane: model.focused, services: services, palette: palette)
                }
            }
            .background(palette.background)
        }
        .background(palette.panel)
        .environment(\.colorScheme, theme.theme.isDark ? .dark : .light)
        .ignoresSafeArea()
    }
}
