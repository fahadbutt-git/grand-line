import AppIcon
import AppKit
import Combine
import DenDenKit

/// Starts the theme, the widgets and one panel per display that should have
/// one, and rebuilds the panels when displays come and go.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = DenDenPaths()
    private var theme: ThemeStore!
    private var host: PanelHost!
    private var controllers: [UInt32: NotchController] = [:]
    private var settingsWindow: SettingsWindow!
    private var statusItem: NSStatusItem?
    private var settingsSink: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        theme = ThemeStore(paths: paths)
        host = PanelHost(paths: paths, theme: theme)
        settingsWindow = SettingsWindow(host: host)
        host.onLayoutChange = { [weak self] in self?.rebuildPanels(force: true) }
        host.openSettings = { [weak self] in self?.showSettings() }
        NSApp.mainMenu = makeMainMenu()
        rebuildPanels(force: false)
        settingsSink = host.$settings
            .map(\.menuBarIcon)
            .removeDuplicates()
            .sink { [weak self] wanted in self?.setStatusItem(wanted) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels(force: false) }
        }
    }

    /// `denden://toggle`, `open`, `close`, `reload` and `settings`, so a keyboard shortcut
    /// (Karabiner, `open -g denden://toggle`) can drive the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "denden" {
            switch url.host ?? url.path {
            case "toggle": targetController()?.toggle()
            case "open": targetController()?.open()
            case "close": controllers.values.forEach { $0.close() }
            case "reload": host.reloadEverything()
            case "settings": showSettings()
            default: break
            }
        }
    }

    @objc func showSettings() {
        settingsWindow.show()
    }

    @objc private func togglePanel() { targetController()?.toggle() }
    @objc private func reloadAll() { host.reloadEverything() }
    @objc private func openWidgetsFolder() { host.user.openFolder() }
    @objc private func openLog() { NSWorkspace.shared.open(Log.file) }

    /// Den Den's menu bar item (`menu_bar_icon`): its glyph, and a menu with
    /// Settings and what the panel's right-click menu has.
    private func setStatusItem(_ wanted: Bool) {
        if !wanted {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = IconRenderer.templateImage(.denDen)
        item.button?.toolTip = "Den Den"
        let menu = NSMenu()
        menu.addItem(withTitle: "Open or close the panel", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reload widgets and theme", action: #selector(reloadAll), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open widgets folder", action: #selector(openWidgetsFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open the log", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Den Den", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// The menus while the Settings window is in front: Command + Comma,
    /// Command + W and Command + Q work as in every Mac app.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu(title: "Den Den")
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Den Den", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Den Den", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window
        return main
    }

    /// The panel on the display with the pointer, else the built-in one.
    private func targetController() -> NotchController? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           let c = controllers[Self.displayID(screen)] { return c }
        return controllers.values.first { $0.model.style == .notch } ?? controllers.values.first
    }

    private func rebuildPanels(force: Bool) {
        let screens = NSScreen.screens
        let infos = screens.map(Self.info(for:))
        let mainID = NSScreen.main.map(Self.displayID)
        let wanted = NotchGeometry.placements(screens: infos, mainID: mainID, external: host.settings.externalDisplays)
        let wantedIDs = Set(wanted.map(\.screenID))

        for (id, c) in controllers where force || !wantedIDs.contains(id) {
            c.tearDown()
            controllers[id] = nil
        }
        for p in wanted {
            guard let info = infos.first(where: { $0.id == p.screenID }) else { continue }
            if let existing = controllers[p.screenID] {
                existing.update(screen: info, style: p.style)
            } else {
                controllers[p.screenID] = NotchController(screen: info, style: p.style, host: host)
            }
        }
    }

    static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func info(for screen: NSScreen) -> ScreenInfo {
        let id = displayID(screen)
        return ScreenInfo(
            id: id,
            frame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            isBuiltin: CGDisplayIsBuiltin(id) != 0
        )
    }
}
