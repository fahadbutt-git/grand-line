import AppKit
import Combine
import LauncherKit
import SwiftUI

/// Whether the window is materialised: the view scales and blurs in and out
/// with it, anchored to the top edge, while the window fades.
@MainActor
final class PanelPresence: ObservableObject {
    @Published var shown = false
}

/// Shows and hides the one resident search window, routes keys to the model,
/// and remembers the app that was in front.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let services: Services
    let model: SearchModel
    let presence = PanelPresence()
    private let panel: SearchPanel
    /// Counts each show and hide, so a fade that finishes late never hides a window shown again.
    private var generation = 0
    /// The window is fading out: still on screen, no longer taking clicks.
    private var dismissing = false
    private var monitor: Any?
    private var colorObserver: NSObjectProtocol?
    private var changes: AnyCancellable?
    private var shadowPending = false
    /// Command + Comma in the search window opens Settings.
    var openSettings: (() -> Void)?
    /// The window was shown (true) or hidden (false).
    var onVisibilityChange: ((Bool) -> Void)?

    init(services: Services) {
        self.services = services
        self.model = SearchModel(services: services)
        self.panel = SearchPanel(size: NSSize(width: Metrics.width + Metrics.preview + 40, height: 560))
        super.init()
        let root = SearchView(model: model, presence: presence)
        panel.contentView = NSHostingView(rootView: root)
        panel.delegate = self
        model.hide = { [weak self] in self?.hide() }
        model.show = { [weak self] in self?.show() }
        // Typing, pasting or pressing a menu item in the app in front needs the keys at once.
        model.performer.willActInFrontApp = { [weak self] in self?.finishDismissal() }
        // The accent or highlight colour changed in System Settings: redraw
        // with it at once (the window takes Light and Dark from macOS itself).
        colorObserver = NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.objectWillChange.send() }
        }
        // App icons are read in the background; the rows redraw when they arrive.
        IconCache.onLoad = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.model.objectWillChange.send()
        }
        // The window is clear, so its shadow follows what is drawn: redraw it
        // as rows change, once per turn of the run loop however many changes
        // came, and never while the window is hidden.
        changes = model.objectWillChange.sink { [weak self] _ in
            guard let self, !self.shadowPending else { return }
            self.shadowPending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.shadowPending = false
                if self.panel.isVisible { self.panel.invalidateShadow() }
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.type == .flagsChanged {
                // Command or Option held: the row and the footer say what Return does then.
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                self.model.setHeld(HeldModifier(command: flags.contains(.command), option: flags.contains(.option),
                                                shift: flags.contains(.shift), control: flags.contains(.control)))
                return event
            }
            return self.route(event) ? nil : event
        }
        // Lay SwiftUI out now, while hidden, so the first open does not pay for it.
        panel.layoutIfNeeded()
    }

    var isVisible: Bool { panel.isVisible && !dismissing }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Whether the window was shown before, for the stall log's label.
    private var shownOnce = false

    /// Shows the window first, with the last results (or an empty field when
    /// they are older than QueryResume allows), and refreshes them on the
    /// next turn of the run loop, so nothing waits on the providers.
    func show() {
        StallPhase.begin(shownOnce ? "show" : "first show")
        defer { StallPhase.end() }
        shownOnce = true
        model.prepareToShow()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            model.performer.previousApp = front
        }
        // Shown again while it fades out: it turns back from where it is, in place.
        if !panel.isVisible {
            position()
            panel.alphaValue = 0
        } else if !dismissing {
            position()
        }
        dismissing = false
        panel.ignoresMouseEvents = false
        generation += 1
        panel.makeKeyAndOrderFront(nil)
        materialise()
        onVisibilityChange?(true)
        // The field exists once SwiftUI has laid the window out, the first time only.
        if model.field == nil { panel.layoutIfNeeded() }
        if let field = model.field {
            panel.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        let shownText = model.text
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            StallPhase.begin("open refresh")
            defer { StallPhase.end() }
            self.services.windowWillOpen(frontApp: self.model.performer.previousApp)
            self.model.panelDidOpen()
            // Typing since the window opened has already searched.
            if self.model.text == shownText { self.model.refresh() }
        }
    }

    /// Hides the window along the path it came in: it fades, scales and blurs
    /// towards its top edge. `animated: false` takes it away at once (Settings
    /// opening, an action that needs the keys in the app in front).
    func hide(animated: Bool = true) {
        StallPhase.begin("hide")
        defer { StallPhase.end() }
        model.actionPanel = nil
        model.didHide()
        let wasVisible = panel.isVisible && !dismissing
        guard wasVisible else {
            if !animated { finishDismissal() }
            return
        }
        onVisibilityChange?(false)
        guard animated else {
            generation += 1
            dismissing = false
            orderOutNow()
            return
        }
        dematerialise()
    }

    /// Fades in and, unless Reduce Motion is on, scales and unblurs from the top edge.
    private func materialise() {
        let reduced = Motion.reduced
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? Motion.fadeDuration : Motion.windowIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // The shadow follows the settled shape, not a frame of the scale.
            MainActor.assumeIsolated { self?.panel.invalidateShadow() }
        }
        withAnimation(reduced ? Motion.fade : Motion.present) { presence.shown = true }
    }

    /// The same path out: the window stops taking clicks at once, fades, and
    /// orders out when the fade ends, unless it was shown again meanwhile.
    private func dematerialise() {
        dismissing = true
        panel.ignoresMouseEvents = true
        generation += 1
        let mine = generation
        let reduced = Motion.reduced
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? Motion.fadeDuration : Motion.windowOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == mine, self.dismissing else { return }
                self.dismissing = false
                self.orderOutNow()
            }
        }
        withAnimation(reduced ? Motion.fade : Motion.present) { presence.shown = false }
    }

    /// Ends a fade at once, so the window no longer holds the keys.
    func finishDismissal() {
        guard dismissing else { return }
        generation += 1
        dismissing = false
        orderOutNow()
    }

    private func orderOutNow() {
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        // Away, so the next show materialises from the same place.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { presence.shown = false }
    }

    /// Centred on the screen with the pointer, a fifth of the way down.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.2 - size.height)
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app hides the window, unless a sheet or open panel took the keys.
        if NSApp.modalWindow == nil, panel.attachedSheet == nil {
            if model.settingsRunningOpen > 0 { model.keysLostDuringSetting = true }
            let justChanged = model.lastSettingEnded.map { Date().timeIntervalSince($0) < 3 } ?? false
            if model.settingsRunningOpen > 0 || justChanged { comeBackIfFinderRestarts() }
            if !dismissing { hide() }
        }
    }

    private var restartWatch: NSObjectProtocol?

    /// Finder relaunched by a setting change (hidden files, desktop icons)
    /// takes the front a moment after the change ends. When that is what took
    /// the keys, the window comes back; any other app taking them is left alone.
    private func comeBackIfFinderRestarts() {
        if let restartWatch { NSWorkspace.shared.notificationCenter.removeObserver(restartWatch) }
        let center = NSWorkspace.shared.notificationCenter
        restartWatch = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundle = app?.bundleIdentifier ?? ""
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopRestartWatch()
                if SearchModel.restartedBySettings.contains(bundle), !self.panel.isVisible { self.show() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.stopRestartWatch() }
        // Finder may already be in front by the time the keys go.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restartWatch != nil, !self.panel.isVisible,
                  let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  SearchModel.restartedBySettings.contains(front) else { return }
            self.stopRestartWatch()
            self.show()
        }
    }

    private func stopRestartWatch() {
        if let restartWatch { NSWorkspace.shared.notificationCenter.removeObserver(restartWatch) }
        restartWatch = nil
    }

    private func route(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let press = KeyPress(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers ?? "",
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
        if flags == .command, event.charactersIgnoringModifiers == ",", let openSettings {
            // Hidden first, so Settings never opens under the floating search window.
            hide(animated: false)
            openSettings()
            return true
        }
        // Command+C with text selected in the field copies that text.
        let fieldSelection = (model.field?.currentEditor()?.selectedRange.length ?? 0) > 0
        if let command = KeyCommand.command(for: press), !(command == .copy && fieldSelection), model.handle(command) {
            return true
        }
        return edit(event.charactersIgnoringModifiers?.lowercased() ?? "", flags: flags)
    }

    /// Command+A, C, V, X, Z and Shift+Command+Z for the field: a menu-bar app
    /// has no Edit menu to send them.
    private func edit(_ key: String, flags: NSEvent.ModifierFlags) -> Bool {
        guard flags == .command || flags == [.command, .shift] else { return false }
        let selector: Selector
        switch (key, flags.contains(.shift)) {
        case ("a", false): selector = #selector(NSText.selectAll(_:))
        case ("c", false): selector = #selector(NSText.copy(_:))
        case ("v", false): selector = #selector(NSText.paste(_:))
        case ("x", false): selector = #selector(NSText.cut(_:))
        case ("z", false): selector = Selector(("undo:"))
        case ("z", true): selector = Selector(("redo:"))
        default: return false
        }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }
}
