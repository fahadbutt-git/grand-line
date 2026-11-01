import AppKit
import Combine
import SwiftUI
import IcebergKit

/// The drop basket (`drag_basket`): shake the pointer while dragging a
/// file and a small basket appears under it. What is dropped in goes on
/// the shelf and is listed in the basket, from where it can be dragged out
/// again. It goes when the drag ends with nothing dropped, on a click
/// outside it, or with its close button.
@MainActor
final class BasketController {
    private let shelf: ShelfModel
    private let theme: ThemeStore
    private let state = BasketState()
    private var panel: NSPanel?
    private var container: BasketContainerView?
    private var clickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    static let size = CGSize(width: 240, height: 160)

    init(shelf: ShelfModel, theme: ThemeStore) {
        self.shelf = shelf
        self.theme = theme
    }

    var isShown: Bool { panel?.isVisible ?? false }

    /// Shows the basket centred on `point` (screen coordinates), kept on its display.
    func show(at point: CGPoint) {
        hideWork?.cancel()
        let panel = self.panel ?? make()
        self.panel = panel
        if !panel.isVisible { state.ids = [] }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var frame = CGRect(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2,
                           width: Self.size.width, height: Self.size.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        }
        panel.setFrame(frame.integral, display: true)
        panel.orderFrontRegardless()
        startClickMonitor()
    }

    /// The drag ended: with nothing dropped and the pointer away, the basket goes.
    func dragEnded() {
        guard isShown else { return }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.state.ids.isEmpty, !(self.container?.containsPointer ?? false) else { return }
                self.hide()
            }
        }
        hideWork = work
        // performDragOperation can arrive just after the button goes up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        stopClickMonitor()
        state.ids = []
        state.targeted = false
        panel?.orderOut(nil)
    }

    private func make() -> NSPanel {
        let panel = NotchPanel.make()
        panel.level = .popUpMenu
        let container = BasketContainerView()
        container.drops.onDrop = { [weak self] urls in
            guard let self else { return }
            let ids = self.shelf.add(urls)
            for id in ids where !self.state.ids.contains(id) { self.state.ids.append(id) }
        }
        container.drops.onHover = { [weak self] on in self?.state.targeted = on }
        container.registerForDraggedTypes([.fileURL])
        let view = BasketView(state: state, shelf: shelf, close: { [weak self] in self?.hide() })
            .environmentObject(theme)
        let hosting = FirstClickHostingView(rootView: AnyView(view))
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        hosting.frame = container.bounds
        self.container = container
        return panel
    }

    private func startClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, panel.isVisible,
                      !panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.hide()
            }
        }
    }

    private func stopClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

@MainActor
final class BasketState: ObservableObject {
    /// The shelf items dropped in this time.
    @Published var ids: [String] = []
    @Published var targeted = false
}

/// The basket's window content: takes dropped files.
final class BasketContainerView: NSView {
    let drops = FileDropTarget()

    var containsPointer: Bool {
        guard let frame = window?.frame else { return false }
        return frame.contains(NSEvent.mouseLocation)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drops.entered(sender) }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drops.entered(sender) }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { drops.exited() }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { drops.perform(sender) }
    }
}

struct BasketView: View {
    @ObservedObject var state: BasketState
    @ObservedObject var shelf: ShelfModel
    let close: () -> Void
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let dropped = shelf.entries.filter { state.ids.contains($0.id) }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionCaption(text: "Basket")
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.muted)
                    .help("Close the basket. What you dropped stays on the shelf.")
            }
            if dropped.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22)).foregroundStyle(theme.highlight)
                    Text("Drop to keep it on the shelf").font(.system(size: 12)).foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(dropped) { entry in ShelfRow(shelf: shelf, entry: entry) }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(theme.panel))
        .overlay(shape.strokeBorder(state.targeted ? theme.highlight : theme.line, lineWidth: state.targeted ? 1.5 : 0.5))
        .clipShape(shape)
        .preferredColorScheme(theme.colorScheme)
    }
}
