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
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "Nexus"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        model.window = window
        window.contentView = NSHostingView(rootView: BrowserRootView(model: model, services: model.services, theme: model.services.theme))
        window.title = model.windowTitle
        window.setFrameAutosaveName("NexusBrowser")
        if model.pinned { window.level = .floating }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc func performBrowserCommand(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let raw = item.representedObject as? String,
              let command = BrowserCommand(rawValue: raw) else { return }
        if TextFieldGuard.forward(command, in: window) { return }
        model.perform(command)
    }

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
    }
}
