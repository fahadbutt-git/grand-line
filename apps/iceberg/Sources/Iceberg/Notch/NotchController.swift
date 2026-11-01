import AppKit
import Combine
import SwiftUI
import IcebergKit

/// One panel on one display: places it, opens it on hover or click, and
/// closes it when the pointer leaves, on a click outside it and on Escape.
///
/// The window is always the shape's size, the notch while closed and the
/// panel while open. Closed, it lets every click through except over the
/// camera housing itself (the top edge of the pill on a display without a
/// notch), so the menu bar, status items and the wings' neighbours below it
/// keep working; a mouse-moved monitor, a rectangle test per event, tells
/// it when the pointer reaches that zone. Opening grows the window first and
/// then animates the shape; closing animates first and then shrinks the
/// window.
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
    /// Mouse-moved monitors (always), and click monitors while open.
    private var moveMonitors: [Any] = []
    private var clickMonitors: [Any] = []
    private var pointerInHitZone = false
    private var dismissal = PanelDismissal()

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

        // The tracking area covers the open panel; the closed one is
        // entered through its hit zone (pointerMoved).
        container.onEnter = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen else { return }
                self.closeWork?.cancel()
            }
        }
        container.onExit = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.model.isOpen else { return }
                self.pointerExited()
            }
        }
        model.onTap = { [weak self] in self?.tapped() }

        panel.setFrame(model.frame(open: false), display: false)
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        refreshClosedVisibility()
        panel.orderFrontRegardless()
        watchPointer()
        observe()
    }

    func close(animated: Bool = true) {
        guard model.isOpen else { return }
        openWork?.cancel()
        closeWork?.cancel()
        stopClickMonitors()
        // A pointer still on the notch must leave and come back to reopen it.
        pointerInHitZone = NotchGeometry.contains(hitZone, NSEvent.mouseLocation)
        if animated {
            withAnimation(closeAnimation) { model.isOpen = false }
        } else {
            model.isOpen = false
        }
        updatePassThrough()
        host.panelDidClose()
        shrinkWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isOpen else { return }
                self.panel.setFrame(self.model.frame(open: false), display: true)
                self.refreshClosedVisibility()
            }
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? (model.reduceMotion ? 0.12 : 0.32) : 0), execute: work)
    }

    /// `byKeyboard`: the shortcut, a URL or the menu bar item, with the
    /// pointer possibly elsewhere (see PanelDismissal).
    func open(byKeyboard: Bool = false) {
        guard !model.isOpen else { return }
        shrinkWork?.cancel()
        closeWork?.cancel()
        openWork?.cancel()
        model.update(content: host.content)
        panel.setFrame(model.frame(open: true), display: true)
        panel.alphaValue = 1
        withAnimation(openAnimation) { model.isOpen = true }
        updatePassThrough()
        dismissal.opened(pointer: NSEvent.mouseLocation, inside: !byKeyboard || container.containsPointer)
        startClickMonitors()
        host.panelWillOpen()
    }

    func toggle(byKeyboard: Bool = false) { model.isOpen ? close() : open(byKeyboard: byKeyboard) }

    func update(screen: ScreenInfo, style: PanelStyle) {
        model.update(screen: screen, style: style)
        panel.setFrame(model.frame(open: model.isOpen), display: true)
        refreshClosedVisibility()
        updatePassThrough()
    }

    func tearDown() {
        close(animated: false)
        for m in moveMonitors { NSEvent.removeMonitor(m) }
        moveMonitors = []
        stopClickMonitors()
        pauseWork?.cancel()
        nowPlayingSink = nil
        bag.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: Pointer

    /// The closed panel's hit zone on this display.
    private var hitZone: CGRect { NotchGeometry.hitZone(of: model.screen, style: model.style) }

    /// The pill goes while the menu bar is hidden (a full-screen app); the
    /// notch, and the open panel, always show.
    private func refreshClosedVisibility() {
        guard !model.isOpen else { panel.alphaValue = 1; return }
        panel.alphaValue = NotchGeometry.closedShapeVisible(on: model.screen, style: model.style) ? 1 : 0
    }

    /// Open: the whole panel takes the pointer. Closed: only the hit zone.
    private func updatePassThrough() {
        let ignores = !model.isOpen && !NotchGeometry.contains(hitZone, NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
    }

    /// A mouse-moved monitor for the other apps (the closed panel lets
    /// their events through) and one for Iceberg's own windows.
    private func watchPointer() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        moveMonitors = [global, local].compactMap { $0 }
    }

    private func pointerMoved() {
        let p = NSEvent.mouseLocation
        if model.isOpen {
            switch dismissal.pointerMoved(to: p, panel: panel.frame) {
            case .armClose: pointerExited()
            case .cancelClose: closeWork?.cancel()
            case .none: break
            }
            return
        }
        let inside = NotchGeometry.contains(hitZone, p)
        updatePassThrough()
        guard inside != pointerInHitZone else { return }
        pointerInHitZone = inside
        if inside { pointerEntered() } else { openWork?.cancel() }
    }

    /// While open: a click anywhere outside the panel closes it. Clicks in
    /// other apps reach the global monitor; one in Iceberg's Settings window
    /// the local one (menus, at their own level, are left alone).
    private func startClickMonitors() {
        stopClickMonitors()
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: buttons) { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: buttons) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = event.window, window !== self.panel, window.level == .normal else { return }
                self.clicked(at: NSEvent.mouseLocation)
            }
            return event
        }
        clickMonitors = [global, local].compactMap { $0 }
    }

    private func stopClickMonitors() {
        for m in clickMonitors { NSEvent.removeMonitor(m) }
        clickMonitors = []
    }

    private func clicked(at p: CGPoint) {
        guard model.isOpen, dismissal.closes(onClickAt: p, panel: panel.frame) else { return }
        close()
    }

    private func pointerEntered() {
        closeWork?.cancel()
        guard host.settings.openOn == .hover, !model.isOpen else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, NotchGeometry.contains(self.hitZone, NSEvent.mouseLocation) else { return }
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
