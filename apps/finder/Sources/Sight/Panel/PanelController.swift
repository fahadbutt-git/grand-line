import AppKit
import Combine
import LauncherKit
import SwiftUI

/// Shows and hides the one resident search window, routes keys to the model,
/// and remembers the app that was in front.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let services: Services
    let model: SearchModel
    let themes = ThemeStore()
    private let panel: SearchPanel
    private var monitor: Any?
    private var changes: AnyCancellable?
    /// Command + Comma in the search window opens Settings.
    var openSettings: (() -> Void)?

    init(services: Services) {
        self.services = services
        self.model = SearchModel(services: services)
        self.panel = SearchPanel(size: NSSize(width: Metrics.width + Metrics.preview + 40, height: 560))
        super.init()
        let root = SearchView(model: model, themes: themes)
        panel.contentView = NSHostingView(rootView: root)
        panel.delegate = self
        model.hide = { [weak self] in self?.hide() }
        model.show = { [weak self] in self?.show() }
        // The window is clear, so its shadow follows what is drawn: redraw it as rows change.
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.panel.invalidateShadow() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.route(event) ? nil : event
        }
        // Lay SwiftUI out now, while hidden, so the first open does not pay for it.
        panel.layoutIfNeeded()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Shows the window first, with the last results, and refreshes them on the
    /// next turn of the run loop, so nothing waits on the providers.
    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            model.performer.previousApp = front
        }
        position()
        panel.appearance = NSAppearance(named: themes.theme.appearanceName)
        panel.makeKeyAndOrderFront(nil)
        // The field exists once SwiftUI has laid the window out, the first time only.
        if model.field == nil { panel.layoutIfNeeded() }
        if let field = model.field {
            panel.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        let shownText = model.text
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.services.windowWillOpen(frontApp: self.model.performer.previousApp)
            self.model.panelDidOpen()
            // Typing since the window opened has already searched.
            if self.model.text == shownText { self.model.refresh() }
        }
    }

    func hide() {
        model.actionPanel = nil
        panel.orderOut(nil)
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
        if NSApp.modalWindow == nil, panel.attachedSheet == nil { hide() }
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
            hide()
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
