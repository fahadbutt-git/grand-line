import Foundation
import SwiftUI
import DenDenKit

/// Everything the panels show, shared by the panel on each display: the
/// settings, the built-in widgets and the user widgets. It also turns "a
/// panel opened" and "the last panel closed" into the widgets' start and stop.
///
/// What shows, and in what order, is `layout`: the `panel` list of
/// denden.toml. Only built-in widgets in it are made; one taken out of it is
/// shut down and let go.
@MainActor
final class PanelHost: ObservableObject {
    let paths: DenDenPaths
    let theme: ThemeStore
    let user: UserWidgets
    let events: SharedEventStore

    @Published private(set) var settings = DenDenSettings()
    @Published private(set) var settingsIssues: [ConfigIssue] = []
    @Published private(set) var builtins: [NotchWidget] = []
    @Published private(set) var layout = PanelLayout(enabled: PanelCatalog.defaultEnabled)

    /// Called when the settings change in a way that moves panels.
    var onLayoutChange: (@MainActor () -> Void)?
    /// Opens the Settings window (set by the app delegate).
    var openSettings: (@MainActor () -> Void)?

    private var made: [String: NotchWidget] = [:]
    private var openPanels = 0
    private var watcher: FileWatcher?

    init(paths: DenDenPaths, theme: ThemeStore) {
        self.paths = paths
        self.theme = theme
        self.user = UserWidgets(paths: paths, theme: theme)
        self.events = SharedEventStore()
        reloadSettings()
        watcher = FileWatcher(paths: [paths.settingsFile]) { [weak self] in self?.reloadSettings() }
    }

    var nowPlaying: NowPlayingWidget? { builtins.first { $0.id == "now-playing" } as? NowPlayingWidget }
    var sections: [NotchWidget] { builtins.filter { $0.placement == .section && $0.isAvailable } }
    var headerWidgets: [NotchWidget] { builtins.filter { $0.placement == .header && $0.isAvailable } }
    var showsDate: Bool { layout.isEnabled("date") }

    /// Settings, theme and widget problems together, errors first. They are
    /// listed in the Settings window, not in the panel.
    var allIssues: [ConfigIssue] {
        let all = settingsIssues + theme.issues + user.issues
        return all.filter { $0.severity == .error } + all.filter { $0.severity == .warning }
    }

    var content: PanelContent {
        PanelContent(sections: sections.count, userWidgets: user.widgets.count, showsIssues: false)
    }

    func reloadSettings() {
        let (loaded, issues) = DenDenSettings.load(from: paths.settingsFile)
        Log.issues(issues, context: "settings")
        settingsIssues = issues
        let newLayout = PanelLayout(settings: loaded)
        let layoutChanged = loaded.externalDisplays != settings.externalDisplays || loaded.liveActivity != settings.liveActivity
            || newLayout.builtins != layout.builtins
        settings = loaded
        if newLayout != layout { layout = newLayout }
        LoginItem.apply(loaded.launchAtLogin)
        let context = WidgetContext(theme: theme, events: events, settings: loaded,
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

    /// Writes one setting to denden.toml (keeping the rest of the file) and
    /// applies it now. Returns what went wrong, or nil.
    @discardableResult
    func save(_ key: String, _ value: TOMLValue) -> String? {
        do {
            try DenDenSettings.write(key, value, to: paths.settingsFile)
        } catch let error as TOMLError {
            return "denden.toml could not be changed: \(error.description). Fix the file and try again."
        } catch {
            return "denden.toml could not be written: \(error.localizedDescription)"
        }
        reloadSettings()
        return nil
    }

    @discardableResult
    func save(_ newLayout: PanelLayout) -> String? {
        save("panel", newLayout.value)
    }

    func reloadEverything() {
        theme.reload()
        reloadSettings()
        user.reload()
    }

    func panelWillOpen() {
        openPanels += 1
        guard openPanels == 1 else { return }
        for w in builtins { w.panelWillOpen() }
        user.panelWillOpen()
    }

    func panelDidClose() {
        openPanels = max(0, openPanels - 1)
        guard openPanels == 0 else { return }
        for w in builtins { w.panelDidClose() }
        user.panelDidClose()
    }
}
