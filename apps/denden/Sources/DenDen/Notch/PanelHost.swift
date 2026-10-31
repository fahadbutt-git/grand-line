import Foundation
import SwiftUI
import DenDenKit

/// Everything the panels show, shared by the panel on each display: the
/// settings, the built-in widgets and the user widgets. It also turns "a
/// panel opened" and "the last panel closed" into the widgets' start and stop.
@MainActor
final class PanelHost: ObservableObject {
    let paths: DenDenPaths
    let theme: ThemeStore
    let user: UserWidgets
    let events: SharedEventStore

    @Published private(set) var settings = DenDenSettings()
    @Published private(set) var settingsIssues: [ConfigIssue] = []
    @Published private(set) var builtins: [NotchWidget] = []

    /// Called when the settings change in a way that moves panels.
    var onLayoutChange: (@MainActor () -> Void)?

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

    /// Settings, theme and widget problems together, errors first.
    var allIssues: [ConfigIssue] {
        let all = settingsIssues + theme.issues + user.issues
        return all.filter { $0.severity == .error } + all.filter { $0.severity == .warning }
    }

    var content: PanelContent {
        PanelContent(sections: sections.count, userWidgets: user.widgets.count,
                     showsIssues: !allIssues.isEmpty)
    }

    func reloadSettings() {
        let (loaded, issues) = DenDenSettings.load(from: paths.settingsFile)
        Log.issues(issues, context: "settings")
        settingsIssues = issues
        let layoutChanged = loaded.externalDisplays != settings.externalDisplays || loaded.liveActivity != settings.liveActivity
            || loaded.builtin != settings.builtin
        settings = loaded
        LoginItem.apply(loaded.launchAtLogin)
        let context = WidgetContext(theme: theme, events: events, settings: loaded)
        builtins = loaded.builtin.compactMap { name in
            if let existing = made[name] { return existing }
            guard let maker = WidgetRegistry.makers[name] else { return nil }
            let w = maker(context)
            made[name] = w
            return w
        }
        if layoutChanged { onLayoutChange?() }
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
