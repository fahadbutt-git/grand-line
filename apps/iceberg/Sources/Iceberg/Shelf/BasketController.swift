import AppKit
import Combine
import SwiftUI
import IcebergKit

/// The drop basket (`drag_basket`): shake the pointer while dragging a
/// file and a small basket appears under it. What is dropped in goes on
/// the shelf and is listed in the basket, from where it can be dragged out
/// again. It goes when the drag ends with nothing dropped, on a click
/// outside it, or with its close button.
///
/// It is a floating surface, so it sits on the system's popover material,
/// in Light or Dark as macOS is, with the window's own shadow. It
/// materialises at the pointer (the window fades, shadow and all, while
/// the content grows and sharpens) and leaves the same way. Shown again
/// while it is leaving, it turns round where it is.
@MainActor
final class BasketController {
    private let shelf: ShelfModel
    private let palette: SystemPalette
    private let state = BasketState()
    private var panel: NSPanel?
    private var container: BasketContainerView?
    private var clickMonitor: Any?
    private var hideWork: DispatchWorkItem?

    static let size = CGSize(width: 240, height: 160)

    init(shelf: ShelfModel, palette: SystemPalette) {
        self.shelf = shelf
        self.palette = palette
    }

    /// Shown, or on its way in: false as soon as it starts to leave.
    var isShown: Bool { state.shown && (panel?.isVisible ?? false) }

    private var reduceMotion: Bool { DisplayOptions.shared.reduceMotion }

    /// Shows the basket centred on `point` (screen coordinates), kept on its display.
    func show(at point: CGPoint) {
        hideWork?.cancel()
        let panel = self.panel ?? make()
        self.panel = panel
        let returning = panel.isVisible
        if !returning || !state.shown { state.ids = [] }
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var frame = CGRect(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2,
                           width: Self.size.width, height: Self.size.height)
        if let visible = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
            frame.origin.y = min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8)
        }
        if !returning || !state.shown {
            panel.setFrame(frame.integral, display: true)
        }
        if !returning { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        fadeWindow(to: 1)
        withAnimation(Motion.basket(reduceMotion: reduceMotion), completionCriteria: .logicallyComplete) {
            state.shown = true
        } completion: { [weak self] in
            // The shadow follows the content once it is full size.
            MainActor.assumeIsolated { self?.panel?.invalidateShadow() }
        }
        startClickMonitor()
    }

    /// The window's alpha, which takes its shadow with it. Starts from
    /// wherever it is, so a show during a hide turns it round.
    private func fadeWindow(to alpha: CGFloat, then done: (@MainActor () -> Void)? = nil) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionSpec.fadeDuration + 0.04
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { done?() }
        }
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
        state.targeted = false
        guard state.shown else { return }
        // Out along the path it came in by; the window goes once it has faded.
        withAnimation(Motion.basket(reduceMotion: reduceMotion)) { state.shown = false }
        fadeWindow(to: 0) { [weak self] in self?.removeIfGone() }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionSpec.settleFallback) { [weak self] in
            MainActor.assumeIsolated { self?.removeIfGone() }
        }
    }

    /// Takes the window away, unless it was shown again meanwhile.
    private func removeIfGone() {
        guard !state.shown, panel?.isVisible == true else { return }
        state.ids = []
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func make() -> NSPanel {
        let panel = NotchPanel.make()
        panel.level = .popUpMenu
        // A floating surface casts the window's shadow, which follows the rounded content.
        panel.hasShadow = true
        let container = BasketContainerView()
        container.drops.onDrop = { [weak self] urls in
            guard let self else { return }
            // The drop carries the drag's momentum into the new row.
            withAnimation(Motion.drop(reduceMotion: self.reduceMotion)) {
                let ids = self.shelf.add(urls)
                for id in ids where !self.state.ids.contains(id) { self.state.ids.append(id) }
            }
        }
        container.drops.onHover = { [weak self] on in
            guard let self, self.state.targeted != on else { return }
            withAnimation(Motion.hover) { self.state.targeted = on }
        }
        container.registerForDraggedTypes([.fileURL])
        let view = BasketView(state: state, shelf: shelf, close: { [weak self] in self?.hide() })
            .environmentObject(palette)
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
    /// Shown (or on its way in); false while it leaves.
    @Published var shown = false
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
    @EnvironmentObject var palette: SystemPalette
    @ObservedObject private var display = DisplayOptions.shared
    @Environment(\.displayScale) private var displayScale

    static let radius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let surface = display.surface
        let dropped = shelf.entries.filter { state.ids.contains($0.id) }
        let edge = state.targeted
            ? palette.highlight
            : palette.line(increaseContrast: surface.edgeEmphasis > 0)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionCaption(text: "Basket", count: dropped.isEmpty ? nil : dropped.count)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(SymbolScale.accessory)
                        .foregroundStyle(palette.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PanelButtonStyle(kind: .icon))
                .help("Close the basket. What you dropped stays on the shelf.")
                .accessibilityLabel("Close the basket")
            }
            if dropped.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(SymbolScale.illustration)
                        .foregroundStyle(palette.highlight)
                        .symbolEffect(.bounce, value: state.targeted)
                    Text("Drop to keep it on the shelf")
                        .font(TypeScale.callout)
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(dropped) { entry in
                            ShelfRow(shelf: shelf, entry: entry)
                                .transition(.materialise(anchor: .top, reduceMotion: display.reduceMotion))
                        }
                    }
                    .padding(.vertical, ScrollEdgeFade.depth)
                }
                .padding(.vertical, -ScrollEdgeFade.depth)
                .mask { ScrollEdgeFade() }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                if surface.usesMaterial {
                    VisualEffectBackground(material: .popover, cornerRadius: Self.radius)
                }
                // Solid only with Reduce Transparency or Increase Contrast.
                shape.fill(palette.background.opacity(surface.tintOpacity))
            }
        }
        .overlay(shape.strokeBorder(edge, lineWidth: PixelGrid.width(pixels: state.targeted ? 3 : surface.edgePixels,
                                                                      scale: displayScale)))
        .clipShape(shape)
        // The window fades (with its shadow); the content grows and sharpens.
        .modifier(Materialise(progress: state.shown ? 1 : 0, anchor: .center, reduceMotion: display.reduceMotion, fades: false))
    }
}
