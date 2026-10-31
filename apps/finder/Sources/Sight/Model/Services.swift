import AppKit
import LauncherKit

/// Builds every provider once and keeps them loaded. Sources are read again in
/// the background when the window opens, at most once a minute.
@MainActor
final class Services {
    let paths = GrandLinePaths()
    let usage: UsageStore
    let rates: CurrencyRatesStore
    let names: NameIndex
    let spotlight = SpotlightSearch()

    let apps = AppCatalog.provider()
    let keybindings = KeybindingsFile.provider()
    let snippets = EspansoMatches.provider()
    let bookmarks = Bookmarks.provider()
    let settings = SettingsPanes.provider()
    /// Settings changed in place: "dark mode", "wifi off", "volume 30".
    let settingsActions = SettingsActionsProvider()
    let symbols = SymbolTable.provider()
    let menuItems = MenuBarItems.provider()
    let menu = MenuProvider()
    let commands = CommandsProvider()
    let web = WebProvider()
    let aliases = AliasProvider()
    let processes = ProcessProvider()
    let saved = SavedSearchProvider()

    private(set) var engine: SearchEngine
    /// Sources, result counts and web engines from Settings.
    private(set) var preferences: SightPreferences
    private var external: [ExternalProvider] = []
    private var lastReload = Date.distantPast

    init() {
        usage = UsageStore(fileURL: URL(fileURLWithPath: paths.usage))
        rates = CurrencyRatesStore(fileURL: URL(fileURLWithPath: paths.rates))
        names = NameIndex(snapshot: URL(fileURLWithPath: paths.index), root: paths.home)
        preferences = SightPreferences(defaults: .standard)
        engine = SearchEngine(providers: [])
        ResultLayout.current = preferences.layout
        web.setEngines(preferences.engines)
        engine = makeEngine()
    }

    /// Settings changed: the next keystroke searches with the new sources,
    /// order, row counts and engines.
    func apply(_ next: SightPreferences) {
        let old = preferences
        preferences = next
        ResultLayout.current = next.layout
        if next.engines != old.engines { web.setEngines(next.engines) }
        if next.sources != old.sources || next.fallbacks != old.fallbacks { engine = makeEngine() }
    }

    func start() {
        names.start()
        reloadSources(force: true)
    }

    func save() {
        try? usage.save()
        names.save()
    }

    private func makeEngine() -> SearchEngine {
        let names = self.names
        let spotlight = self.spotlight
        let saved = self.saved
        let files = FilesProvider(
            paths: paths,
            names: { text, limit in await names.search(text, limit: limit) },
            spotlight: { text, limit in await spotlight.run(text, limit: limit, savedSearch: { saved.query(named: $0) }) },
            unreadable: { await names.unreadable() }
        )
        let sources = preferences.sources
        var providers: [any LaunchProvider] = [
            RecentsProvider(usage: usage),
            CalculatorProvider(rates: rates, arithmetic: sources.isEnabled(.calculator), conversions: sources.isEnabled(.units)),
            settingsActions,
            aliases, apps, menu, commands, keybindings, settings, menuItems, processes,
            DefineProvider(lookup: { DictionaryLookup.define($0) }),
            snippets, symbols, bookmarks, web, files, saved,
            WindowsProvider(), PathProvider(),
            ReminderProvider(paths: paths), ShellProvider(paths: paths), ClipboardProvider(),
            PrefixListProvider(keywords: external.map { (keyword: $0.config.keyword, title: $0.config.title) }),
            FallbackProvider(fallbacks: preferences.fallbacks),
        ]
        // Sources turned off in Settings, Sources.
        providers = providers.filter { sources.runs(providerID: $0.id) }
        providers += external.map { $0 as any LaunchProvider }
        return SearchEngine(providers: providers, ranker: Ranker(usage: usage, aliases: aliases.aliases))
    }

    /// Reads every source again. Without `force`, only when the last read is over a minute old.
    func reloadSources(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastReload) > 60 else { return }
        lastReload = Date()
        let catalogs = [apps, keybindings, snippets, bookmarks]
        let symbols = self.symbols
        let commands = self.commands, web = self.web, saved = self.saved, menu = self.menu, paths = self.paths
        Task.detached(priority: .utility) {
            for catalog in catalogs { catalog.reload() }
            if symbols.catalog.count == 0 { symbols.reload() }
            commands.reload()
            web.reload()
            saved.reload()
            await menu.reload()
            let table = AliasTable.parse((try? String(contentsOfFile: paths.aliases, encoding: .utf8)) ?? "")
            let configs = ExternalProviderConfig.parse((try? String(contentsOfFile: paths.externalProviders, encoding: .utf8)) ?? "")
            await MainActor.run { self.apply(aliases: table, external: configs) }
        }
        let rates = self.rates
        Task.detached(priority: .utility) {
            await rates.refreshIfStale { url in try await URLSession.shared.data(from: url).0 }
        }
    }

    private func apply(aliases table: AliasTable, external configs: [ExternalProviderConfig]) {
        let changed = table != aliases.aliases || configs != external.map(\.config)
        aliases.set(table)
        external = configs.map { ExternalProvider($0) }
        if changed { engine = makeEngine() }
    }

    /// What the window needs fresh each time it opens: the running apps, the
    /// front app's menus and the menu's ticks.
    func windowWillOpen(frontApp: NSRunningApplication?) {
        processes.set(RunningApps.list())
        reloadSources()
        let menuItems = self.menuItems
        guard let frontApp, frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = frontApp.processIdentifier
        let name = frontApp.localizedName ?? "App"
        Task.detached(priority: .userInitiated) {
            menuItems.replace(MenuBarReader.results(pid: pid, app: name))
        }
    }
}
