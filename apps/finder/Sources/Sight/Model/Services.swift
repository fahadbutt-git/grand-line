import AppKit
import IndexKit
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
    /// "selection": actions on what is selected in Nexus or Finder.
    let selection = SelectionProvider()
    /// `:` Maccy's history, read only.
    let clipboardHistory = ClipboardHistoryProvider()
    /// Executables in ~/.config/grand-line/sight/scripts that print rows.
    let scripts = ScriptCommandsProvider()

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
        // Keyword providers and script commands, for the `/` list.
        var keywords: [(keyword: String, title: String)] = external.map { (keyword: $0.config.keyword, title: $0.config.title) }
        keywords += scripts.providers.map { (keyword: $0.script.name, title: "Script: " + $0.script.name) }
        var providers: [any LaunchProvider] = [
            RecentsProvider(usage: usage),
            CalculatorProvider(rates: rates, arithmetic: sources.isEnabled(.calculator), conversions: sources.isEnabled(.units)),
            settingsActions,
            aliases, apps, menu, commands, keybindings, settings, menuItems, processes,
            DefineProvider(lookup: { DictionaryLookup.define($0) }),
            snippets, symbols, bookmarks, web, files, saved,
            WindowsProvider(), PathProvider(),
            ReminderProvider(paths: paths), ShellProvider(paths: paths), ClipboardProvider(), clipboardHistory,
            selection, scripts,
            PrefixListProvider(keywords: keywords),
            FallbackProvider(fallbacks: preferences.fallbacks),
            FallbackCommandsProvider(paths: paths),
        ]
        // Sources turned off in Settings, Sources.
        providers = providers.filter { sources.runs(providerID: $0.id) }
        providers += external.map { $0 as any LaunchProvider }
        providers += scripts.providers.map { $0 as any LaunchProvider }
        return SearchEngine(providers: providers, ranker: Ranker(usage: usage, aliases: aliases.aliases))
    }

    /// Reads every source again. Without `force`, only when the last read is over a minute old.
    func reloadSources(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastReload) > 60 else { return }
        lastReload = Date()
        let catalogs = [apps, keybindings, snippets, bookmarks]
        let symbols = self.symbols
        let commands = self.commands, web = self.web, saved = self.saved, menu = self.menu, paths = self.paths
        let scripts = self.scripts
        Task.detached(priority: .utility) {
            // Reading app bundles, the symbol table and the config files blocks
            // for as long as the disk takes. It runs on a Dispatch queue, not on
            // the concurrency pool, which has a thread per core: at launch these
            // reads used to hold it while the first search waited for a thread.
            let read = await BlockingWork.run { () -> SourcesRead in
                for catalog in catalogs { catalog.reload() }
                if symbols.catalog.count == 0 { symbols.reload() }
                commands.reload()
                let before = scripts.providers.map(\.script)
                scripts.reload()
                let scriptsChanged = scripts.providers.map(\.script) != before
                web.reload()
                saved.reload()
                let table = AliasTable.parse((try? String(contentsOfFile: paths.aliases, encoding: .utf8)) ?? "")
                let configs = ExternalProviderConfig.parse((try? String(contentsOfFile: paths.externalProviders, encoding: .utf8)) ?? "")
                return SourcesRead(aliases: table, external: configs, scriptsChanged: scriptsChanged)
            }
            await menu.reload()
            await MainActor.run { self.apply(aliases: read.aliases, external: read.external, scriptsChanged: read.scriptsChanged) }
        }
        let rates = self.rates
        Task.detached(priority: .utility) {
            await rates.refreshIfStale { url in try await URLSession.shared.data(from: url).0 }
        }
    }

    private func apply(aliases table: AliasTable, external configs: [ExternalProviderConfig], scriptsChanged: Bool) {
        let changed = scriptsChanged || table != aliases.aliases || configs != external.map(\.config)
        aliases.set(table)
        external = configs.map { ExternalProvider($0) }
        if changed { engine = makeEngine() }
    }

    /// What the window needs fresh each time it opens: the running apps, the
    /// front app's menus and the menu's ticks.
    func windowWillOpen(frontApp: NSRunningApplication?) {
        names.warm()
        processes.set(RunningApps.list())
        reloadSources()
        readSelection(frontApp: frontApp)
        let history = clipboardHistory
        BlockingWork.start { history.reload() }
        let menuItems = self.menuItems
        guard let frontApp, frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = frontApp.processIdentifier
        let name = frontApp.localizedName ?? "App"
        // Walking another app's menus through Accessibility waits on that app,
        // for seconds when it is busy: on a Dispatch queue, never on the pool
        // the searches run on.
        BlockingWork.start(qos: .userInitiated) {
            menuItems.replace(MenuBarReader.results(pid: pid, app: name))
        }
    }

    /// What "selection" acts on, read as lib/bin-common.sh's finder_selection
    /// does: Nexus's state file when Nexus was in front, else Finder's
    /// selection through AppleScript (in the background; it may ask for
    /// Automation the first time).
    private func readSelection(frontApp: NSRunningApplication?) {
        let selection = self.selection
        switch frontApp?.bundleIdentifier {
        case ActionPerformer.nexus:
            selection.set(SelectionProvider.readNexus(paths.nexusSelection), from: "Nexus")
        case "com.apple.finder":
            selection.set([], from: "Finder")
            Task.detached(priority: .userInitiated) {
                let output = try? await ShellRunner().run("/usr/bin/osascript", ["-e", SelectionProvider.finderScript], timeout: 3)
                selection.set(SelectionProvider.parse(output?.stdout ?? ""), from: "Finder")
            }
        default:
            selection.set([], from: "")
        }
    }
}

/// What a reload of the sources read, for the main actor to apply.
private struct SourcesRead: @unchecked Sendable {
    let aliases: AliasTable
    let external: [ExternalProviderConfig]
    let scriptsChanged: Bool
}
