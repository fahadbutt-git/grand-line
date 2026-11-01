import Foundation
import SwiftUI
import IcebergKit

/// Everything the panels show, shared by the panel on each display: the
/// settings, the built-in widgets and the user widgets. It also turns "a
/// panel opened" and "the last panel closed" into the widgets' start and stop.
///
/// What shows, and in what order, is `layout`: the `panel` list of
/// iceberg.toml. Only built-in widgets in it are made; one taken out of it is
/// shut down and let go.
@MainActor
final class PanelHost: ObservableObject {
    let paths: IcebergPaths
    let theme: ThemeStore
    let user: UserWidgets
    let events: SharedEventStore
    /// The shelf (files dropped on the notch or the basket), kept across restarts.
    let shelf: ShelfModel
    /// Notices files being dragged in any app (the shelf and the basket).
    let drag = DragWatcher()
    /// The HUDs in the notch.
    let hud = HUDCenter()

    @Published private(set) var settings = IcebergSettings()
    @Published private(set) var settingsIssues: [ConfigIssue] = []
    @Published private(set) var builtins: [NotchWidget] = []
    @Published private(set) var layout = PanelLayout(enabled: PanelCatalog.defaultEnabled)

    /// Called when the settings change in a way that moves panels.
    var onLayoutChange: (@MainActor () -> Void)?
    /// Opens the Settings window (set by the app delegate).
    var openSettings: (@MainActor () -> Void)?
    /// A panel opened (the app delegate's hang watchdog watches a while).
    var onPanelOpen: (@MainActor () -> Void)?
    /// Escape was pressed while a panel is open (closes them).
    var onEscape: (@MainActor () -> Void)?

    /// The keyboard shortcut that opens or closes the panel (`toggle_shortcut`).
    let hotKey: HotKey
    /// Escape, held only while a panel is open: the panel is never key, so
    /// this is how Escape reaches it. Let go the moment the last one closes.
    private let escapeKey: HotKey
    /// Why the shortcut could not be registered, for Settings.
    @Published private(set) var hotKeyProblem: String?
    /// When iceberg.toml was last read (hot reload), for Settings.
    @Published private(set) var lastSettingsReload: Date?

    private var made: [String: NotchWidget] = [:]
    /// What Login Items were last set to, nil before the first good read.
    private var appliedLoginItem: Bool?
    private var openPanels = 0
    private var configWatcher: ConfigWatcher?
    private var fallbackWatchers: [FileWatcher] = []
    private var triggerObserver: DistributedObserver?

    /// The distributed notification `iceberg trigger NAME` posts; its object is the widget's name.
    static let triggerNotification = "com.grandline.iceberg.trigger"

    init(paths: IcebergPaths, theme: ThemeStore) {
        self.paths = paths
        self.theme = theme
        self.user = UserWidgets(paths: paths, theme: theme)
        self.events = SharedEventStore()
        self.shelf = ShelfModel(paths: paths)
        self.hotKey = HotKey()
        self.escapeKey = HotKey(id: 2)
        escapeKey.action = { [weak self] in self?.onEscape?() }
        reloadSettings()
        watchConfig()
        triggerObserver = DistributedObserver(Self.triggerNotification) { [weak self] note in
            guard let name = note.object as? String, !name.isEmpty else { return }
            self?.user.trigger(name)
        }
    }

    /// Hot reload: iceberg.toml, the widget files and their scripts are read
    /// again when saved, with no restart.
    private func watchConfig() {
        if let watcher = ConfigWatcher(folder: paths.configFolder, onChange: { [weak self] changed, rescan in
            self?.configChanged(changed, rescan: rescan)
        }) {
            configWatcher = watcher
            return
        }
        Log.info("FSEvents would not watch \(paths.configFolder.path); watching the folders instead")
        fallbackWatchers = [
            FileWatcher(paths: [paths.settingsFile]) { [weak self] in self?.reloadSettings() },
            FileWatcher(paths: [paths.widgetsFolder]) { [weak self] in self?.user.reload() },
        ]
    }

    /// Sorts the saved files: iceberg.toml reloads the settings, files in
    /// widgets/ reload the widgets (and re-run those whose script changed).
    func configChanged(_ changed: [String], rescan: Bool) {
        let settingsName = paths.settingsFile.lastPathComponent
        let widgetsName = paths.widgetsFolder.lastPathComponent
        var settingsChanged = rescan
        var widgetsChanged = rescan
        var names: [String] = []
        for path in changed {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            let parent = url.deletingLastPathComponent().lastPathComponent
            if name == settingsName && parent != widgetsName {
                settingsChanged = true
            } else if parent == widgetsName {
                widgetsChanged = true
                names.append(name)
            } else if name == widgetsName || name == paths.configFolder.lastPathComponent {
                // The folder itself was made, moved or replaced.
                settingsChanged = true
                widgetsChanged = true
            }
        }
        if settingsChanged { reloadSettings() }
        if widgetsChanged { user.filesChanged(names) }
    }

    var nowPlaying: NowPlayingWidget? { builtins.first { $0.id == "now-playing" } as? NowPlayingWidget }
    var sections: [NotchWidget] { builtins.filter { $0.placement == .section && $0.isAvailable } }
    var headerWidgets: [NotchWidget] { builtins.filter { $0.placement == .header && $0.isAvailable } }
    var showsDate: Bool { layout.isEnabled("date") }
    /// The panel takes dropped files while the shelf is in it.
    var takesFiles: Bool { layout.isEnabled("shelf") }

    /// Settings, theme and widget problems together, errors first. They are
    /// listed in the Settings window, not in the panel.
    var allIssues: [ConfigIssue] {
        let all = settingsIssues + theme.issues + user.issues
        return all.filter { $0.severity == .error } + all.filter { $0.severity == .warning }
    }

    var content: PanelContent {
        PanelContent(sections: sections.count, userWidgets: user.widgets.count, showsIssues: false)
    }

    /// Reads iceberg.toml again. A file that cannot be used (a syntax error,
    /// a save caught half-way) keeps the settings in use: nothing is torn
    /// down, and Login Items, the menu bar item and the shortcut stay as
    /// they are. Login Items follow the file only when the setting changes.
    func reloadSettings() {
        let first = lastSettingsReload == nil
        let read = IcebergSettings.reload(from: paths.settingsFile, previous: first ? nil : settings)
        Log.issues(read.issues, context: "settings")
        if read.issues != settingsIssues { settingsIssues = read.issues }
        if read.keptPrevious {
            lastSettingsReload = Date()
            Log.info("iceberg.toml could not be used; keeping the last good settings")
            return
        }
        let loaded = read.settings
        let newLayout = PanelLayout(settings: loaded)
        let layoutChanged = loaded.externalDisplays != settings.externalDisplays || loaded.liveActivity != settings.liveActivity
            || newLayout.builtins != layout.builtins
        let shortcutChanged = loaded.toggleShortcut != settings.toggleShortcut || lastSettingsReload == nil
        if loaded != settings { settings = loaded }
        lastSettingsReload = Date()
        if newLayout != layout { layout = newLayout }
        if LoginItemPolicy.shouldApply(wanted: loaded.launchAtLogin, applied: appliedLoginItem, fileUsable: read.fileUsable) {
            LoginItem.apply(loaded.launchAtLogin)
            appliedLoginItem = loaded.launchAtLogin
        }
        user.setMaxConcurrent(loaded.maxConcurrent)
        if shortcutChanged { hotKeyProblem = hotKey.register(loaded.toggleShortcut) }
        applyFeatures(loaded, layout: newLayout)
        let context = WidgetContext(theme: theme, events: events, settings: loaded, shelf: shelf,
                                    availabilityChanged: { [weak self] in self?.objectWillChange.send() })
        let wanted = newLayout.builtins
        for (name, widget) in made where !wanted.contains(name) {
            widget.shutDown()
            made[name] = nil
        }
        builtins = wanted.compactMap { name in
            if let existing = made[name] { return existing }
            guard let maker = WidgetRegistry.makers[name] else { return nil }
            let w = maker(context)
            made[name] = w
            if openPanels > 0 { w.panelWillOpen() }
            return w
        }
        user.show(newLayout.enabled)
        if layoutChanged { onLayoutChange?() }
    }

    /// The shelf, the drag watcher and the HUDs follow the settings: what
    /// is turned off is stopped (its monitors and listeners removed).
    private func applyFeatures(_ settings: IcebergSettings, layout: PanelLayout) {
        if shelf.quickActionsEnabled != settings.shelfQuickActions { shelf.quickActionsEnabled = settings.shelfQuickActions }
        drag.shakeEnabled = settings.dragBasket
        drag.setActive(layout.isEnabled("shelf") || settings.dragBasket)
        hud.apply(settings)
    }

    /// Writes one setting to iceberg.toml (keeping the rest of the file) and
    /// applies it now. Returns what went wrong, or nil.
    @discardableResult
    func save(_ key: String, _ value: TOMLValue) -> String? {
        do {
            try IcebergSettings.write(key, value, to: paths.settingsFile)
        } catch let error as TOMLError {
            return "iceberg.toml could not be changed: \(error.description). Fix the file and try again."
        } catch {
            return "iceberg.toml could not be written: \(error.localizedDescription)"
        }
        reloadSettings()
        return nil
    }

    @discardableResult
    func save(_ newLayout: PanelLayout) -> String? {
        save("panel", newLayout.value)
    }

    /// Settings records a new shortcut: the current one must not fire meanwhile.
    func suspendShortcut() { hotKey.suspend() }

    func resumeShortcut() { hotKeyProblem = hotKey.resume() }

    func reloadEverything() {
        theme.reload()
        reloadSettings()
        user.reload()
    }

    func panelWillOpen() {
        onPanelOpen?()
        openPanels += 1
        guard openPanels == 1 else { return }
        escapeKey.register(HotKey.escape)
        for w in builtins { w.panelWillOpen() }
        user.panelWillOpen()
    }

    func panelDidClose() {
        openPanels = max(0, openPanels - 1)
        guard openPanels == 0 else { return }
        escapeKey.register(nil)
        for w in builtins { w.panelDidClose() }
        user.panelDidClose()
    }
}
