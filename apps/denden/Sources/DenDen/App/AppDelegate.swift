import AppKit
import DenDenKit

/// Starts the theme, the widgets and one panel per display that should have
/// one, and rebuilds the panels when displays come and go.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let paths = DenDenPaths()
    private var theme: ThemeStore!
    private var host: PanelHost!
    private var controllers: [UInt32: NotchController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        theme = ThemeStore(paths: paths)
        host = PanelHost(paths: paths, theme: theme)
        host.onLayoutChange = { [weak self] in self?.rebuildPanels(force: true) }
        rebuildPanels(force: false)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels(force: false) }
        }
    }

    /// `denden://toggle`, `open`, `close` and `reload`, so a keyboard shortcut
    /// (Karabiner, `open -g denden://toggle`) can drive the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "denden" {
            switch url.host ?? url.path {
            case "toggle": targetController()?.toggle()
            case "open": targetController()?.open()
            case "close": controllers.values.forEach { $0.close() }
            case "reload": host.reloadEverything()
            default: break
            }
        }
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
