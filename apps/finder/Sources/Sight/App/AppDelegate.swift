import AppKit
import LaunchKit
import LauncherKit
import ServiceManagement
import ThemeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: Services!
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var saveTimer: Timer?
    private var preferences: SightPreferencesStore!
    private var settings: SightSettingsWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        services = Services()
        panel = PanelController(services: services)
        preferences = SightPreferencesStore(services: services)
        settings = SightSettingsWindow(services: services, themes: panel.themes, store: preferences)
        wireSettings()
        if !registerHotkey(preferences.hotkey), preferences.hotkey == .commandSpace { explainBusyShortcut() }
        if preferences.current.launchAtLogin { startAtLogin() }
        if preferences.current.showMenuBarIcon { statusItem = makeStatusItem() }
        applyDensity()
        services.start()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.services.save() }
        }
    }

    /// `open -b com.grandline.sight` on a running Sight shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    /// `sight://settings[/pane]`: the Settings window (the launcher's
    /// "sight settings" and the main menu's Settings entries use it).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "sight" && (url.host ?? "") == "settings" {
            panel.hide()
            settings.show(pane: url.pathComponents.dropFirst().first)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.save()
    }

    // MARK: Settings

    private func wireSettings() {
        panel.openSettings = { [weak self] in self?.showSettings() }
        preferences.onHotkeyChange = { [weak self] hotkey in self?.registerHotkey(hotkey) ?? false }
        preferences.onRecording = { [weak self] recording in
            guard let self else { return }
            // The shortcut being recorded must reach the field, not open the window.
            if recording { self.hotKey = nil } else { self.registerHotkey(self.preferences.hotkey) }
        }
        preferences.onMenuBarIconChange = { [weak self] shown in
            guard let self else { return }
            if shown, self.statusItem == nil { self.statusItem = self.makeStatusItem() }
            if !shown, let item = self.statusItem {
                NSStatusBar.system.removeStatusItem(item)
                self.statusItem = nil
            }
        }
        preferences.onDensityChange = { [weak self] in self?.applyDensity() }
        // A menu-bar app has no menu bar of its own; the Settings window gets
        // one while it is in front, so Cmd+W, Cmd+Q and editing keys work there.
        settings.onKeyChange = { key in
            NSApp.mainMenu = key ? AppDelegate.settingsMenu() : nil
        }
    }

    @objc func showSettings() {
        panel.hide()
        settings.show()
    }

    private func applyDensity() {
        Metrics.row = CGFloat(Density.current(theme: panel.themes.theme, defaults: .standard).scaled(30))
        panel.model.objectWillChange.send()
    }

    /// Registers the launcher shortcut, replacing the one before. Returns false
    /// when macOS refused it (another app or Spotlight holds it).
    @discardableResult
    private func registerHotkey(_ shortcut: LauncherHotkey?) -> Bool {
        hotKey = nil
        guard let shortcut else { return true }
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in self?.panel.toggle() }
        return hotKey != nil
    }

    // MARK: Menu bar

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Sight")
        let menu = NSMenu()
        menu.addItem(withTitle: "Search", action: #selector(showPanel), keyEquivalent: " ").target = self
        menu.addItem(withTitle: "Reload sources", action: #selector(reload), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    /// The menus while the Settings window is in front.
    static func settingsMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(title: "Sight")
        app.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Sight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        for menu in [app, edit, window] {
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        return main
    }

    @objc private func showPanel() { panel.show() }
    @objc private func reload() { services.reloadSources(force: true) }

    /// Sight must be running for its shortcut to work, so it starts at login
    /// unless Settings, General says otherwise.
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
        alert.informativeText = "Restart the Mac or log out and in once, and Command + Space opens Sight. Its menu bar icon opens it until then."
        alert.runModal()
    }
}
