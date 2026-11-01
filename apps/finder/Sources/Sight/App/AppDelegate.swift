import AppKit
import AppRuntime
import LaunchKit
import LauncherKit
import ServiceManagement
import ThemeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var services: Services!
    private var panel: PanelController!
    private var hotKey = HotkeyRegistration<HotKey>()
    private var statusItem: NSStatusItem?
    private var saveTimer: Timer?
    private var preferences: SightPreferencesStore!
    private var settings: SightSettingsWindow!
    /// ~/Library/Logs/grand-line/sight.log: stalls, crashes.
    private let log = AppLog(name: "sight")
    private lazy var watchdog = HangWatchdog(log: log)
    private lazy var crashRecord = CrashGuard(name: "sight", log: log)
    /// Present while the search window is open: the unattended update waits.
    private let busy = BusyMarker(name: "sight")
    private var activeObservers: [NSObjectProtocol] = []
    private var termination: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // After three crashes in ten minutes Sight stays closed (and says so once).
        guard crashRecord.launch(displayName: "Sight") else { exit(0) }
        termination = TerminationSignal.handle { DispatchQueue.main.async { MainActor.assumeIsolated { NSApp.terminate(nil) } } }
        services = Services()
        // Connect to the index service first, so the first search finds it ready.
        services.start()
        panel = PanelController(services: services)
        preferences = SightPreferencesStore(services: services)
        settings = SightSettingsWindow(services: services, themes: panel.themes, store: preferences)
        wireSettings()
        watchMainThread()
        if !registerHotkey(preferences.hotkey) {
            if preferences.hotkey == .commandSpace { explainBusyShortcut() } else { preferences.noteRefusedAtLaunch() }
        }
        if preferences.current.launchAtLogin { startAtLogin() }
        if preferences.current.showMenuBarIcon { statusItem = makeStatusItem() }
        applyDensity()
        // Every half hour, writing only when something was learned; macOS
        // may fold the wake-up in with others (tolerance a tenth of it).
        let timer = Timer(timeInterval: 1_800, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.services.save() }
        }
        timer.tolerance = 180
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
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
            openSettings(pane: url.pathComponents.dropFirst().first)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services?.save()
        busy.set("panel", busy: false)
        crashRecord.quitCleanly()
    }

    /// The hang watchdog: while Sight is in front, and for a while after the
    /// search window was last opened.
    private func watchMainThread() {
        let center = NotificationCenter.default
        let dog = watchdog
        activeObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in dog.setActive(true) },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in dog.setActive(false) },
        ]
        let busy = self.busy
        panel.onVisibilityChange = { visible in
            if visible { dog.noteUse() }
            busy.set("panel", busy: visible)
        }
    }

    // MARK: Settings

    private func wireSettings() {
        panel.openSettings = { [weak self] in self?.showSettings() }
        preferences.onHotkeyChange = { [weak self] hotkey in self?.registerHotkey(hotkey) ?? false }
        preferences.onRecording = { [weak self] recording in
            guard let self else { return }
            // The shortcut being recorded must reach the field, not open the window.
            if recording { self.hotKey.suspend() } else { self.registerHotkey(self.preferences.hotkey) }
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
        settings.onKeyChange = { [weak self] key in
            NSApp.mainMenu = key ? AppDelegate.settingsMenu() : nil
            // Settings in front never sits under the search window.
            if key { self?.panel.hide() }
        }
    }

    /// Every way into Settings (Cmd+, in the search window, the menu bar
    /// item, sight://settings) hides the search window first, then brings
    /// Settings to the front.
    @objc func showSettings() {
        openSettings(pane: nil)
    }

    private func openSettings(pane: String?) {
        panel.hide()
        settings.show(pane: pane)
    }

    private func applyDensity() {
        Metrics.row = CGFloat(Density.current(theme: panel.themes.theme, defaults: .standard).scaled(30))
        panel.model.objectWillChange.send()
    }

    /// Registers the launcher shortcut, then lets the one before go. Returns
    /// false when macOS refused it (another app or Spotlight holds it); the
    /// shortcut before it then keeps working.
    @discardableResult
    private func registerHotkey(_ shortcut: LauncherHotkey?) -> Bool {
        hotKey.change(to: shortcut) { wanted in
            HotKey(keyCode: wanted.keyCode, modifiers: wanted.modifiers) { [weak self] in self?.panel.toggle() }
        }
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
    /// Said once, in a notification: Sight starts in the background (login,
    /// setup, an update), so it never puts up a dialog that would take the
    /// keyboard from what you are doing.
    private func explainBusyShortcut() {
        guard ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1" else { return }
        let key = "ExplainedBusyShortcut"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        QuietNotice.post(title: "Command + Space still opens Spotlight",
                         message: "Restart the Mac or log out and in once, and it opens Sight. The menu bar icon opens Sight until then.")
    }
}
