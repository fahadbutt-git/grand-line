import AppKit
import Combine
import SwiftUI
import IcebergKit

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
    private var pauseWork: DispatchWorkItem?
    private var bag: Set<AnyCancellable> = []
    private var nowPlayingSink: AnyCancellable?
    private weak var watchedNowPlaying: NowPlayingWidget?
    /// When the music paused, so the wings stay a little after.
    private var pausedAt: Date?
    private var wasPlaying = false

    /// How long the wings stay, with still bars, after the music pauses.
    private static let pauseGrace: TimeInterval = 20

    // Springs, or short fades with Reduce Motion.
    private var openAnimation: Animation {
        model.reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)
    }
    private var closeAnimation: Animation {
        model.reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 1)
    }
    private var wingAnimation: Animation? {
        model.reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88)
    }

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
            withAnimation(closeAnimation) { model.isOpen = false }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? (model.reduceMotion ? 0.12 : 0.32) : 0), execute: work)
    }

    func open() {
        guard !model.isOpen else { return }
        shrinkWork?.cancel()
        closeWork?.cancel()
        model.update(content: host.content)
        panel.setFrame(model.frame(open: true), display: true)
        withAnimation(openAnimation) { model.isOpen = true }
        host.panelWillOpen()
    }

    func toggle() { model.isOpen ? close() : open() }

    func update(screen: ScreenInfo, style: PanelStyle) {
        model.update(screen: screen, style: style)
        panel.setFrame(model.frame(open: model.isOpen), display: true)
    }

    func tearDown() {
        close(animated: false)
        pauseWork?.cancel()
        nowPlayingSink = nil
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
                self.watchNowPlaying()
                self.syncLiveActivity()
                if self.model.isOpen, self.model.expandedPanelSize != before {
                    self.panel.setFrame(self.model.frame(open: true), display: true)
                }
            }
            .store(in: &bag)

        // Music starting or stopping widens or narrows the closed notch.
        watchNowPlaying()
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                self?.model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
            .store(in: &bag)
        syncLiveActivity()
    }

    /// Follows the Now Playing widget, which comes and goes as it is turned
    /// on and off in Settings.
    private func watchNowPlaying() {
        let current = host.nowPlaying
        guard current !== watchedNowPlaying || (current != nil && nowPlayingSink == nil) else { return }
        watchedNowPlaying = current
        nowPlayingSink = current?.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncLiveActivity() }
    }

    /// The wings show while music plays, and for a short while after it
    /// pauses (with still, low bars). Nothing playing, or Now Playing
    /// turned off, and the notch is its own width again.
    private func syncLiveActivity() {
        pauseWork?.cancel()
        let player = host.nowPlaying
        let playing = player?.isPlaying ?? false
        if wasPlaying && !playing { pausedAt = Date() }
        if playing { pausedAt = nil }
        wasPlaying = playing
        var wanted = host.settings.liveActivity && player != nil && playing
        if !wanted, host.settings.liveActivity, player?.state.hasMedia == true, let paused = pausedAt {
            let left = Self.pauseGrace - Date().timeIntervalSince(paused)
            if left > 0 {
                wanted = true
                let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.syncLiveActivity() } }
                pauseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + left + 0.05, execute: work)
            }
        }
        guard wanted != model.showsLiveActivity else { return }
        if model.isOpen {
            model.showsLiveActivity = wanted
            return
        }
        if wanted {
            // Grow the window, then the shape.
            let size = NotchGeometry.collapsedPanelSize(of: model.screen, liveActivity: true)
            panel.setFrame(NotchGeometry.topCentred(size, on: model.screen), display: true)
            withAnimation(wingAnimation) { model.showsLiveActivity = true }
        } else {
            withAnimation(wingAnimation) { model.showsLiveActivity = false }
            let delay = model.reduceMotion ? 0 : 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.model.isOpen, !self.model.showsLiveActivity else { return }
                    self.panel.setFrame(self.model.frame(open: false), display: true)
                }
            }
        }
    }
}
