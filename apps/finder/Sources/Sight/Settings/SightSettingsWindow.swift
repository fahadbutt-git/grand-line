import AppKit
import IndexKit
import LaunchKit
import LauncherKit
import SettingsKit
import SwiftUI
import ThemeKit

/// Sight's Settings window (Cmd+, while the search window is in front, the
/// menu bar item, `sight://settings[/pane]`, and the query "sight settings"):
/// General, Sources, Search, Web, Appearance and Advanced.
@MainActor
final class SightSettingsWindow {
    static let idPrefix = "sight"

    let store: SightPreferencesStore
    private let services: Services
    private let themes: ThemeStore
    private var controller: SettingsWindowController?
    /// Called as the window comes forward and goes back, to put up the menus.
    var onKeyChange: ((Bool) -> Void)?

    init(services: Services, themes: ThemeStore, store: SightPreferencesStore) {
        self.services = services
        self.themes = themes
        self.store = store
    }

    var isVisible: Bool { controller?.isVisible ?? false }

    func show(pane: String? = nil) {
        let controller = self.controller ?? make()
        self.controller = controller
        controller.show(pane: pane)
    }

    private func make() -> SettingsWindowController {
        let theme = SettingsTheme(themes.theme, updates: themes.$theme.eraseToAnyPublisher())
        let store = self.store
        let services = self.services
        let appearance = AppearanceModel(theme: theme)
        appearance.onDensityChange = { store.densityChanged($0) }
        let index = IndexStatusModel(provider: { services.names })
        let update = UpdateModel()
        let prefix = Self.idPrefix
        let panes = [
            SettingsPane("general", title: "General", symbol: "gearshape") {
                SightGeneralPane(store: store, theme: theme)
            },
            SettingsPane("sources", title: "Sources", symbol: "square.stack.3d.up") {
                SightSourcesPane(store: store)
            },
            SettingsPane("search", title: "Search", symbol: "magnifyingglass") {
                SightSearchPane(store: store, index: index, home: services.paths.home)
            },
            SettingsPane("web", title: "Web", symbol: "globe") {
                SightWebPane(store: store)
            },
            SettingsPane("appearance", title: "Appearance", symbol: "paintpalette") {
                AppearancePane(model: appearance, idPrefix: prefix)
            },
            SettingsPane("advanced", title: "Advanced", symbol: "slider.horizontal.3") {
                SightAdvancedPane(store: store, update: update, paths: services.paths)
            },
        ]
        let controller = SettingsWindowController(appName: "Sight", idPrefix: prefix, theme: theme, panes: panes)
        controller.onKeyChange = { [weak self] key in self?.onKeyChange?(key) }
        return controller
    }
}

private func settingID(_ suffix: String) -> String { "sight.settings." + suffix }

// MARK: General

struct SightGeneralPane: View {
    @ObservedObject var store: SightPreferencesStore
    @ObservedObject var theme: SettingsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Shortcut", note: "Caps + Space sends Command + Space, so it opens Sight while the shortcut is Command + Space.") {
                SettingsRow("Open Sight", detail: shortcutDetail) {
                    HStack(spacing: 8) {
                        HotkeyRecorder(
                            hotkey: store.hotkey,
                            textColor: NSColor(theme.theme.text), dimColor: NSColor(theme.theme.dim),
                            fieldColor: NSColor(theme.theme.field), accentColor: NSColor(theme.theme.highlight),
                            onRecord: { store.setHotkey($0) },
                            onRecording: { store.onRecording?($0) }
                        )
                        .frame(width: 150, height: 24)
                        Button("Default") { store.setHotkey(nil) }
                            .disabled(store.defaults.object(forKey: HotkeySetting.hotkeyKey) == nil)
                            .help("Command + Space, once setup has turned Spotlight's shortcut off")
                            .accessibilityIdentifier(settingID("general.hotkeyDefault"))
                    }
                }
                if let problem = store.hotkeyProblem {
                    SettingsRow(problem, symbol: "exclamationmark.triangle")
                }
            }
            SettingsSection("Sight") {
                SettingsToggle("Show Sight in the menu bar", detail: "Without it, open Settings with Cmd+, in the search window.",
                               id: settingID("general.menuBarIcon"), isOn: binding(\.showMenuBarIcon))
                SettingsToggle("Open at login", detail: "Sight has to be running for its shortcut to work.",
                               id: settingID("general.login"), isOn: binding(\.launchAtLogin))
                SettingsToggle("Close the window after changing a setting",
                               detail: "\u{201C}wifi off\u{201D} and the like; otherwise it stays open so a second Return undoes it.",
                               id: settingID("general.closeAfterSetting"), isOn: binding(\.closeAfterSettingChange))
            }
        }
    }

    private var shortcutDetail: String {
        if store.hotkey == nil {
            return "None yet: setup gives Sight Command + Space when it turns Spotlight's shortcut off. Record one here to use it now."
        }
        return "Click the field and press the keys. Escape cancels."
    }

    private func binding(_ key: WritableKeyPath<SightPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.current[keyPath: key] }, set: { value in store.update { $0[keyPath: key] = value } })
    }
}

// MARK: Sources

struct SightSourcesPane: View {
    @ObservedObject var store: SightPreferencesStore

    var body: some View {
        let sources = store.current.sources
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Sources", note: "Turn a kind of result off, or move it to change where its section shows. A prefix shows that source alone.") {
                ForEach(Array(sources.order.enumerated()), id: \.element) { index, source in
                    SettingsRow(source.title, detail: source.detail, symbol: source.symbol) {
                        HStack(spacing: 10) {
                            if let prefix = source.prefix {
                                Text(prefix.display)
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .frame(height: 18)
                                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.4)))
                                    .help("Type \(prefix.display) first to search \(source.title.lowercased()) alone")
                                    .accessibilityLabel("Prefix \(prefix.display)")
                            }
                            ReorderButtons(canMoveUp: index > 0, canMoveDown: index < sources.order.count - 1) { offset in
                                store.update { $0.sources.move(source, by: offset) }
                            }
                            Toggle(source.title, isOn: Binding(
                                get: { sources.isEnabled(source) },
                                set: { on in store.update { $0.sources.set(source, enabled: on) } }))
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                                .accessibilityIdentifier(settingID("sources.\(source.rawValue)"))
                                .accessibilityLabel(source.title)
                        }
                    }
                }
            }
            HStack {
                Button("Restore Defaults") { store.update { $0.sources = .standard } }
                    .disabled(sources == .standard)
                    .accessibilityIdentifier(settingID("sources.reset"))
                Spacer()
            }
            SettingsNote("Your own sources go in ~/.config/grand-line/sight/providers.tsv; aliases in aliases.tsv.")
        }
    }
}

// MARK: Search

struct SightSearchPane: View {
    @ObservedObject var store: SightPreferencesStore
    @ObservedObject var index: IndexStatusModel
    let home: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Files", note: "Sight finds names in the home folder through the index Nexus shares. Nexus's Settings set where searches start and rebuild the index.") {
                SettingsRow("Folders", detail: "~ (the home folder), with ~/Library/CloudStorage for Google Drive")
                SettingsRow("Left out", detail: exclusions)
                SettingsRow("Index settings") {
                    Button("Open Nexus Settings › Search") {
                        if let url = URL(string: "nexus://settings/search") { NSWorkspace.shared.open(url) }
                    }
                    .accessibilityIdentifier(settingID("search.openNexus"))
                }
            }
            IndexStatusSection(model: index, idPrefix: SightSettingsWindow.idPrefix, allowsRebuild: false, home: home)
            SettingsSection("Rows per section", note: "How many results each section shows. A prefix shows eight times as many.") {
                ForEach(ResultLayout.adjustable, id: \.self) { section in
                    let count = store.current.limits[section] ?? section.limit
                    SettingsRow(section.title) {
                        Stepper(value: Binding(
                            get: { count },
                            set: { value in store.update { $0.limits[section] = value == section.limit ? nil : value } }),
                                in: ResultLayout.limitRange) {
                            Text("\(count)").font(.system(size: 13).monospacedDigit()).frame(width: 24, alignment: .trailing)
                        }
                        .accessibilityIdentifier(settingID("search.limit.\(section.name)"))
                        .accessibilityLabel("\(section.title) rows")
                    }
                }
            }
        }
    }

    private var exclusions: String {
        let names = IndexExclusions.standard.names.sorted().prefix(12).joined(separator: ", ")
        return "~/Library (except \(HomeIndexScope.kept.sorted().joined(separator: ", "))), \(names), and app bundles as one item"
    }
}

// MARK: Web

struct SightWebPane: View {
    @ObservedObject var store: SightPreferencesStore
    @Local private var name = ""
    @Local private var url = ""
    @Local private var keyword = ""
    @Local private var problem: String? = nil

    var body: some View {
        let engines = store.current.engines
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Search engines", note: "Type the keyword and your words (\u{201C}pm glaucoma\u{201D}), or ? for every engine. Ticked engines also show at the bottom of every search.") {
                ForEach(Array(engines.enumerated()), id: \.element.id) { index, engine in
                    SettingsRow(engine.name, detail: engine.template, symbol: engine.search.symbol) {
                        HStack(spacing: 10) {
                            Text(engine.keyword.isEmpty ? "no keyword" : engine.keyword)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Toggle("Fallback", isOn: Binding(
                                get: { engine.fallback },
                                set: { on in store.update { $0.engines[index].fallback = on } }))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 12))
                                .accessibilityIdentifier(settingID("web.fallback.\(engine.id)"))
                            ReorderButtons(canMoveUp: index > 0, canMoveDown: index < engines.count - 1) { offset in
                                store.update { prefs in
                                    let to = min(max(index + offset, 0), prefs.engines.count - 1)
                                    prefs.engines.swapAt(index, to)
                                }
                            }
                            Button {
                                store.update { _ = $0.engines.remove(at: index) }
                            } label: {
                                Image(systemName: "minus.circle").font(.system(size: 12))
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(engine.name)")
                            .accessibilityLabel("Remove \(engine.name)")
                        }
                    }
                }
                if engines.isEmpty {
                    SettingsRow("No engines. Add one below, or restore the defaults.")
                }
            }
            SettingsSection("Add an engine") {
                SettingsRow("Name") { field("PubMed", text: $name, id: "web.new.name") }
                SettingsRow("URL", detail: "%s stands for the search words.") {
                    field("https://pubmed.ncbi.nlm.nih.gov/?term=%s", text: $url, id: "web.new.url", width: 300)
                }
                SettingsRow("Keyword", detail: "Optional, one word.") { field("pm", text: $keyword, id: "web.new.keyword", width: 80) }
                SettingsRow(problem ?? "", symbol: problem == nil ? nil : "exclamationmark.triangle") {
                    Button("Add Engine", action: add)
                        .disabled(name.isEmpty || url.isEmpty)
                        .accessibilityIdentifier(settingID("web.add"))
                }
            }
            SettingsSection("Also at the bottom of every search") {
                SettingsToggle("Search Drive contents", id: settingID("web.drive"), isOn: Binding(
                    get: { store.current.driveFallback }, set: { on in store.update { $0.driveFallback = on } }))
                SettingsToggle("Ask Claude, ChatGPT and Gemini", id: settingID("web.assistants"), isOn: Binding(
                    get: { store.current.assistantFallbacks }, set: { on in store.update { $0.assistantFallbacks = on } }))
            }
            HStack {
                Button("Restore Default Engines") { store.update { $0.engines = WebEngineList.standard } }
                    .disabled(engines == WebEngineList.standard)
                Spacer()
            }
            SettingsNote("Quicklinks in ~/.config/grand-line/sight/quicklinks.tsv add to these.")
        }
    }

    private func field(_ prompt: String, text: Binding<String>, id: String, width: CGFloat = 180) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .onSubmit(add)
            .accessibilityIdentifier(settingID(id))
    }

    private func add() {
        let key = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        if let why = WebEngine.problem(name: name, template: url, keyword: key) {
            problem = why
            return
        }
        if !key.isEmpty, store.current.engines.contains(where: { $0.keyword == key }) {
            problem = "Another engine uses \u{201C}\(key)\u{201D}."
            return
        }
        let engine = WebEngine(name: name.trimmingCharacters(in: .whitespaces), template: url.trimmingCharacters(in: .whitespaces),
                               keyword: key, fallback: false)
        store.update { $0.engines.append(engine) }
        name = ""
        url = ""
        keyword = ""
        problem = nil
    }
}

// MARK: Advanced

struct SightAdvancedPane: View {
    @ObservedObject var store: SightPreferencesStore
    @ObservedObject var update: UpdateModel
    let paths: GrandLinePaths
    @Local private var result: String? = nil
    @Local private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Sources") {
                SettingsRow("Read every source again", detail: "Apps, menus, commands, snippets and bookmarks. Sight also does this when the window opens, once a minute at most.") {
                    Button("Reload Sources") {
                        store.reloadSources()
                        result = "Sources are being read again."
                    }
                    .accessibilityIdentifier(settingID("advanced.reload"))
                }
                SettingsRow("Logs", detail: "~/Library/Logs/grand-line") {
                    Button("Open Logs") {
                        FolderOpener.open(URL(fileURLWithPath: paths.home + "/Library/Logs/grand-line", isDirectory: true))
                    }
                }
                SettingsRow("Settings folder", detail: paths.abbreviate(paths.settings)) {
                    Button("Open Folder") { FolderOpener.open(URL(fileURLWithPath: paths.settings, isDirectory: true)) }
                }
            }
            SettingsSection("Learned ranking", note: "Sight ranks what you pick higher. Resetting moves usage.json to the Trash, so it can be put back.") {
                SettingsRow("Reset usage history", detail: "Rankings, recents and favourites start fresh.") {
                    Button("Reset…") { confirming = true }
                        .accessibilityIdentifier(settingID("advanced.resetUsage"))
                }
                if let result {
                    SettingsRow(result, symbol: "info.circle")
                }
            }
            .confirmationDialog("Reset Sight's usage history?", isPresented: $confirming) {
                Button("Move to Trash", role: .destructive) { result = store.resetUsage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("usage.json goes to the Trash. Rankings, recents and favourites start fresh.")
            }
            UpdateSection(model: update, idPrefix: SightSettingsWindow.idPrefix,
                          note: "Rebuilds Sight, Nexus and Iceberg from the package and reopens them.")
        }
    }
}
