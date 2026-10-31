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
        guard SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    /// macOS applies the switch from Spotlight's shortcut at the next login.
    private func explainBusyShortcut() {
        let alert = NSAlert()
        alert.messageText = "Command + Space still opens Spotlight"
        alert.informativeText = "Restart the Mac or log out and in once, and Command + Space opens Byakugan. Its menu bar icon opens it until then."
        alert.runModal()
    }
}
