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
/// then animates the shape; closing animates first and then fits the
/// window once the spring has finished (not after a fixed wait). Every
/// spring starts from what is on screen, so a hover that comes back while
/// the panel closes reverses it in place; nothing waits for an animation.
@MainActor
final class NotchController {
    let model: NotchModel
    private let host: PanelHost
    private let panel: NotchPanel
    private let container: HoverContainerView
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    /// Counts the changes that fit the window afterwards: only the latest one does.
    private var settleToken = 0
    private var pauseWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?
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

    // Critically damped springs (MotionSpec): opening on hover must not
    // overshoot. Short cross-fades with Reduce Motion.
    private var openAnimation: Animation { Motion.open(reduceMotion: model.reduceMotion) }
    private var closeAnimation: Animation { Motion.close(reduceMotion: model.reduceMotion) }
    private var wingAnimation: Animation { Motion.wings(reduceMotion: model.reduceMotion) }

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
        // Files dropped on the open panel go on the shelf (while it is turned on).
        // The drop carries the drag's momentum, so the new row settles with a small bounce.
        container.drops.onDrop = { [weak host] urls in
            withAnimation(Motion.drop(reduceMotion: DisplayOptions.shared.reduceMotion)) { _ = host?.shelf.add(urls) }
        }
        container.drops.onHover = { [weak host] on in
            guard let host, host.shelf.isDropTargeted != on else { return }
            withAnimation(Motion.hover) { host.shelf.isDropTargeted = on }
        }
        container.setTakesFiles(host.takesFiles)

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
        animate(animated ? closeAnimation : nil) { model.isOpen = false }
        updatePassThrough()
        host.panelDidClose()
    }

    /// `byKeyboard`: the shortcut, a URL or the menu bar item, with the
    /// pointer possibly elsewhere (see PanelDismissal).
    func open(byKeyboard: Bool = false) {
        guard !model.isOpen else { return }
        settleToken &+= 1
        closeWork?.cancel()
        openWork?.cancel()
        model.update(content: host.content)
        hudWork?.cancel()
        model.hud = nil
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
        hudWork?.cancel()
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
        // A file dragged near the notch opens the panel at once, to drop it on the shelf.
        if host.takesFiles, host.drag.isFileDrag,
           NotchGeometry.contains(NotchGeometry.dropZone(of: model.screen, style: model.style), p) {
            open()
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
                self.container.setTakesFiles(self.host.takesFiles)
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
        if model.hud != nil {
            // A HUD is showing in a wider window; the wings follow when it goes.
            model.showsLiveActivity = wanted
            return
        }
        if wanted {
            // Grow the window, then the shape.
            let size = NotchGeometry.collapsedPanelSize(of: model.screen, liveActivity: true)
            settleToken &+= 1
            panel.setFrame(NotchGeometry.topCentred(size, on: model.screen), display: true)
            withAnimation(wingAnimation) { model.showsLiveActivity = true }
        } else {
            animate(wingAnimation) { model.showsLiveActivity = false }
        }
    }

    // MARK: HUDs

    /// Shows a HUD beside the closed notch for a moment; a new one replaces
    /// it and starts the wait again. Nothing shows while the panel is open.
    func showHUD(_ event: HUDEvent) {
        guard !model.isOpen else { return }
        hudWork?.cancel()
        if model.hud == nil {
            // Grow the window, then the shape.
            settleToken &+= 1
            panel.setFrame(NotchGeometry.topCentred(NotchGeometry.hudPanelSize(of: model.screen), on: model.screen), display: true)
            panel.alphaValue = 1
            withAnimation(wingAnimation) { model.hud = event }
        } else if model.hud != event {
            // The level and its text follow in place (HUDView).
            model.hud = event
        }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hideHUD() } }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HUDEvent.duration, execute: work)
    }

    private func hideHUD() {
        guard model.hud != nil, !model.isOpen else { return }
        animate(wingAnimation) { model.hud = nil }
    }

    // MARK: Fitting the window after a spring

    /// Runs `change` with `animation`, then fits the closed window to the
    /// shape once the spring has logically finished: SwiftUI's own
    /// completion, not a guess at its length. Any later change (opening,
    /// growing the wings again) supersedes it, so an interrupted spring
    /// never shrinks the window under the one that replaced it.
    private func animate(_ animation: Animation?, _ change: () -> Void) {
        settleToken &+= 1
        let token = settleToken
        let fit: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.settle(token) }
        }
        guard let animation else {
            change()
            fit()
            return
        }
        withAnimation(animation, completionCriteria: .logicallyComplete, change, completion: fit)
        // Should SwiftUI not report the end (nothing drawn meanwhile), fit it anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionSpec.settleFallback, execute: fit)
    }

    private func settle(_ token: Int) {
        guard token == settleToken else { return }
        settleToken &+= 1
        guard !model.isOpen else { return }
        panel.setFrame(model.frame(open: false), display: true)
        refreshClosedVisibility()
    }
}
