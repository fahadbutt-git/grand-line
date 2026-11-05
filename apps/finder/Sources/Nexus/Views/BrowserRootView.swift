import BrowserKit
import SwiftUI

/// The window: sidebar, toolbar, panes, preview and inspector, footer.
/// The sidebar sits on the macOS sidebar material; the toolbar shares the
/// content's background, as a unified toolbar does, and meets the content in
/// a soft edge rather than a hard rule. Panels slide in and out along the
/// same edge on critically damped springs, and cross-fade with Reduce Motion.
struct BrowserRootView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var services: Services
    @ObservedObject var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = theme.palette
        HStack(spacing: 0) {
            if model.showSidebar {
                HStack(spacing: 0) {
                    SidebarView(model: model, sidebar: services.sidebar, palette: palette)
                        .frame(width: model.sidebarWidth)
                    ResizeHandle(palette: palette, onDrag: { model.sidebarWidth = SidebarMetrics.clamp($0) }, current: model.sidebarWidth)
                }
                .transition(Motion.slide(.leading, reduceMotion))
            }
            VStack(spacing: 0) {
                if model.showToolbar {
                    ToolbarView(model: model, palette: palette)
                        .transition(Motion.slide(.top, reduceMotion))
                } else {
                    Color.clear.frame(height: 28)
                }
                HStack(spacing: 0) {
                    PaneArea(model: model, palette: palette)
                        .popover(isPresented: $model.showViewOptions, arrowEdge: .top) {
                            ViewOptionsView(model: model, pane: model.focused, palette: palette)
                        }
                    if model.showPreview {
                        HStack(spacing: 0) {
                            Hairline(palette: palette, axis: .vertical)
                            PreviewPane(pane: model.focused, palette: palette).frame(width: 320)
                        }
                        .transition(Motion.slide(.trailing, reduceMotion))
                    }
                    if model.showInspector {
                        HStack(spacing: 0) {
                            Hairline(palette: palette, axis: .vertical)
                            InspectorView(model: model, pane: model.focused, palette: palette).frame(width: 280)
                        }
                        .transition(Motion.slide(.trailing, reduceMotion))
                    }
                }
                .overlay(alignment: .top) {
                    if model.showToolbar { EdgeFade(palette: palette) }
                }
                .clipped()
                if model.showStatusBar {
                    VStack(spacing: 0) {
                        Hairline(palette: palette)
                        FooterView(model: model, pane: model.focused, services: services, palette: palette)
                    }
                    .transition(Motion.slide(.bottom, reduceMotion))
                }
            }
            .background(palette.background)
        }
        .animation(Motion.panel(reduceMotion), value: model.showSidebar)
        .animation(Motion.panel(reduceMotion), value: model.showPreview)
        .animation(Motion.panel(reduceMotion), value: model.showInspector)
        .animation(Motion.panel(reduceMotion), value: model.showStatusBar)
        .animation(Motion.panel(reduceMotion), value: model.showToolbar)
        .sheet(isPresented: Binding(get: { !model.batchRenameItems.isEmpty },
                                    set: { if !$0 { model.batchRenameItems = [] } })) {
            BatchRenameSheet(model: model, items: model.batchRenameItems, palette: palette)
        }
        .environment(\.colorScheme, theme.theme.isDark ? .dark : .light)
        .ignoresSafeArea()
    }
}
