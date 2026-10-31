import AppKit
import LaunchKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: Services!
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var saveTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = Services()
        panel = PanelController(services: services)
        if HotkeySetting.takesCommandSpace() {
            hotKey = HotKey(keyCode: HotKey.space, modifiers: HotKey.command) { [weak self] in self?.panel.toggle() }
            if hotKey == nil { explainBusyShortcut() }
        }
        startAtLogin()
        statusItem = makeStatusItem()
        services.start()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.services.save() }
        }
    }

    /// `open -b com.grandline.byakugan` on a running Byakugan shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.save()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Byakugan")
        let menu = NSMenu()
        menu.addItem(withTitle: "Search", action: #selector(showPanel), keyEquivalent: " ").target = self
        menu.addItem(withTitle: "Reload sources", action: #selector(reload), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Byakugan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    @objc private func showPanel() { panel.show() }
    @objc private func reload() { services.reloadSources(force: true) }

    /// Byakugan must be running for Command + Space to work, so it starts at login.
    private func startAtLogin() {
        // A test run starts a temporary copy that must not become a login item.
        guard ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1" else { return }
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    /// macOS applies the switch from Spotlight's shortcut at the next login.
    /// Shown once, after launch has finished, so whatever started the app
    /// (setup, login) never waits on the dialog.
    private func explainBusyShortcut() {
        guard ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1" else { return }
        let key = "ExplainedBusyShortcut"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.async { Self.showBusyShortcutAlert() }
    }

    private static func showBusyShortcutAlert() {
        let alert = NSAlert()
        alert.messageText = "Command + Space still opens Spotlight"
        alert.informativeText = "Restart the Mac or log out and in once, and Command + Space opens Byakugan. Its menu bar icon opens it until then."
        alert.runModal()
    }
}
