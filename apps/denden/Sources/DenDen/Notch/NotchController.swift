import AppKit
import Combine
import SwiftUI
import DenDenKit

/// One panel on one display: places it, opens it on hover or click, and
/// closes it when the pointer leaves.
///
/// The window is always exactly the shape's size, the notch while closed and
/// the panel while open, so it never covers the menu bar beside the notch and
/// needs no global mouse monitor. Opening grows the window first and then
/// animates the shape; closing animates first and then shrinks the window.
@MainActor
final class NotchController {
    let model: NotchModel
    private let host: PanelHost
    private let panel: NotchPanel
    private let container: HoverContainerView
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var bag: Set<AnyCancellable> = []

    private static let openAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
    private static let closeAnimation = Animation.spring(response: 0.28, dampingFraction: 1)

    init(screen: ScreenInfo, style: PanelStyle, host: PanelHost) {
        self.host = host
        panel = NotchPanel.make()
        container = HoverContainerView()
        model = NotchModel(screen: screen, style: style)
        model.update(content: host.content)

        let root = NotchRootView(model: model, host: host, theme: host.theme)
        let hosting = FirstClickHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        container.autoresizesSubviews = true
        panel.contentView = container
        hosting.frame = container.bounds

        container.onEnter = { [weak self] in MainActor.assumeIsolated { self?.pointerEntered() } }
        container.onExit = { [weak self] in MainActor.assumeIsolated { self?.pointerExited() } }
        model.onTap = { [weak self] in self?.tapped() }

        panel.setFrame(model.frame(open: false), display: false)
        panel.orderFrontRegardless()
        observe()
    }

    func close(animated: Bool = true) {
        guard model.isOpen else { return }
        openWork?.cancel()
        closeWork?.cancel()
        if animated {
            withAnimation(Self.closeAnimation) { model.isOpen = false }
        } else {
            model.isOpen = false
        }
        host.panelDidClose()
        shrinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isOpen else { return }
                self.panel.setFrame(self.model.frame(open: false), display: true)
            }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.32 : 0), execute: work)
    }

    func open() {
        guard !model.isOpen else { return }
        shrinkWork?.cancel()
        closeWork?.cancel()
        model.update(content: host.content)
        panel.setFrame(model.frame(open: true), display: true)
        withAnimation(Self.openAnimation) { model.isOpen = true }
        host.panelWillOpen()
    }

    func toggle() { model.isOpen ? close() : open() }

    func update(screen: ScreenInfo, style: PanelStyle) {
        model.update(screen: screen, style: style)
        panel.setFrame(model.frame(open: model.isOpen), display: true)
    }

    func tearDown() {
        close(animated: false)
        bag.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Pointer

    private func pointerEntered() {
        closeWork?.cancel()
        guard host.settings.openOn == .hover, !model.isOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.container.containsPointer else { return }
                self.open()
            }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + host.settings.hoverDelay, execute: work)
    }

    private func pointerExited() {
        openWork?.cancel()
        guard model.isOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.container.containsPointer else { return }
                self.close()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + host.settings.closeDelay, execute: work)
    }

    private func tapped() {
        if !model.isOpen { open() }
        else if host.settings.openOn == .click { close() }
    }

    // MARK: Keeping the size right

    private func observe() {
        // The open panel's height follows the widget list and problems.
        host.objectWillChange.merge(with: host.user.objectWillChange, host.theme.objectWillChange)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let before = self.model.expandedPanelSize
                self.model.update(content: self.host.content)
                self.syncLiveActivity()
                if self.model.isOpen, self.model.expandedPanelSize != before {
                    self.panel.setFrame(self.model.frame(open: true), display: true)
                }
            }
            .store(in: &bag)

        // Music starting or stopping widens or narrows the closed notch.
        host.nowPlaying?.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncLiveActivity() }
            .store(in: &bag)
        syncLiveActivity()
    }

    private func syncLiveActivity() {
        let wanted = host.settings.liveActivity && (host.nowPlaying?.isPlaying ?? false)
        guard wanted != model.showsLiveActivity else { return }
        if model.isOpen {
            model.showsLiveActivity = wanted
            return
        }
        if wanted {
            // Grow the window, then the shape.
            model.showsLiveActivity = true
            let size = model.collapsedPanelSize
            panel.setFrame(NotchGeometry.topCentred(size, on: model.screen), display: true)
        } else {
            withAnimation(Self.closeAnimation) { model.showsLiveActivity = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.model.isOpen, !self.model.showsLiveActivity else { return }
                    self.panel.setFrame(self.model.frame(open: false), display: true)
                }
            }
        }
    }
}
