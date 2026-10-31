import AppKit
import BrowserKit
import Quartz
import SwiftUI

/// A browser window. It answers the menu bar through the responder chain and
/// controls the Quick Look panel for its selection (R13).
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let model: BrowserModel

    init(model: BrowserModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 640, height: 400)
        window.tabbingMode = NexusPreferencesStore.tabbingMode(NexusPreferencesStore.shared.current)
        window.tabbingIdentifier = "Nexus"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        model.window = window
        window.contentView = NSHostingView(rootView: BrowserRootView(model: model, services: model.services, theme: model.services.theme))
        window.title = model.windowTitle
        window.setFrameAutosaveName("NexusBrowser")
        if model.pinned { window.level = .floating }
        watchFilterEscape()
    }

    private var escapeMonitor: Any?

    /// Escape clears the omnibar's filter and closes its bar wherever the keys
    /// are. The list handles it when it has the keys; after Return in the
    /// filter field they may be with the window itself, which ignored Escape,
    /// so the filter and its bar stayed (`FilterEscape`).
    private func watchFilterEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.keyCode == 53, let self, let window = self.window, event.window === window, window.isKeyWindow,
                      !self.model.editingPath else { return event }
                let pane = self.model.focused
                let modifiers = FileListCoordinator.modifiers(event.modifierFlags)
                guard FilterEscape.clears(filter: pane.state.filter, typing: TextFieldGuard.isTyping(in: window),
                                          modifiers: modifiers, sheetOpen: window.attachedSheet != nil) else { return event }
                self.model.clearFilter(in: pane)
                return nil
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc func performBrowserCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let raw = item.representedObject as? String,
              let command = BrowserCommand(rawValue: raw) else { return }
        let traced = Self.traced.contains(command)
        if TextFieldGuard.forward(command, in: window) {
            if traced { NexusLog.note("menu \(command.rawValue): went to the text field being edited") }
            return
        }
        if traced {
            NexusLog.note("menu \(command.rawValue): to the files (keys with \(TextFieldGuard.describeKeys(in: window)); folder \(model.focused.location.folderURL?.path ?? "none"); \(model.focused.selectedItems.count) selected)")
        }
        model.perform(command)
    }

    /// Commands whose arrival is logged, for the clipboard's trail in nexus.log.
    static let traced: Set<BrowserCommand> = [.copy, .cut, .paste, .moveHere]

    /// The tab bar's + button, as in Finder.
    override func newWindowForTab(_ sender: Any?) {
        model.perform(.newTab)
    }

    @objc func openWithApp(_ sender: Any?) {
        guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
        model.openWith(url)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performBrowserCommand(_:)),
              let raw = menuItem.representedObject as? String, let command = BrowserCommand(rawValue: raw) else { return true }
        menuItem.state = model.isChecked(command) ? .on : .off
        if let editing = TextFieldGuard.validate(menuItem, command, in: window) {
            menuItem.title = CommandCatalog.spec(command).title
            return editing
        }
        menuItem.title = model.title(for: command)
        return model.isEnabled(command)
    }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) {
        model.selectionChanged()
    }

    func windowWillClose(_ notification: Notification) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        model.tearDown()
        WindowManager.shared.closed(self)
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = QuickLook.shared
        panel.delegate = QuickLook.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
        QuickLook.shared.panelClosed()
    }
}
