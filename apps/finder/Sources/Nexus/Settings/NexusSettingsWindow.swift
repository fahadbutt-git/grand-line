import AppKit
import BrowserKit
import FileKit
import IndexKit
import SettingsKit
import SwiftUI
import ThemeKit

/// Nexus's Settings window (Cmd+,, `nexus://settings[/pane]`, and the
/// launcher's "nexus settings"): General, Sidebar, Tags, Views, Search,
/// Appearance and Advanced. Every control changes Nexus's defaults domain or
/// the file the setting already lives in, and applies to open windows at once.
@MainActor
final class NexusSettingsWindow {
    static let shared = NexusSettingsWindow()
    static let idPrefix = "nexus"

    /// The index the Search pane reports on and rebuilds. The shared index
    /// service's client today; whatever conforms to `IndexStatusProviding` can
    /// take its place here.
    static var indexProvider: @MainActor () -> (any IndexStatusProviding)? = { Services.shared.index }

    private var controller: SettingsWindowController?
    private var escapeMonitor: Any?

    func show(pane: String? = nil) {
        let controller = self.controller ?? make()
        self.controller = controller
        controller.show(pane: pane)
        watchEscape()
    }

    /// Escape closes Settings, as in every macOS settings window, unless a
    /// field is being edited (then Escape is the field's). Cmd+W and the close
    /// button close it through the menu and the window itself.
    private func watchEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let window = NexusSettingsWindow.shared.controller?.window, window.isKeyWindow,
                      !(window.firstResponder is NSText) else { return event }
                window.performClose(nil)
                return nil
            }
        }
    }

    private func make() -> SettingsWindowController {
        let services = Services.shared
        let theme = SettingsTheme(services.theme.theme, updates: services.theme.$theme.eraseToAnyPublisher())
        let store = NexusPreferencesStore.shared
        let appearance = AppearanceModel(theme: theme)
        appearance.onDensityChange = { store.densityChanged($0) }
        let index = IndexStatusModel(provider: { NexusSettingsWindow.indexProvider() })
        let update = UpdateModel(home: services.paths.home)
        let prefix = Self.idPrefix
        let panes = [
            SettingsPane("general", title: "General", symbol: "gearshape") {
                NexusGeneralPane(store: store)
            },
            SettingsPane("sidebar", title: "Sidebar", symbol: "sidebar.left") {
                NexusSidebarPane(store: store, services: services, sidebar: services.sidebar)
            },
            SettingsPane("tags", title: "Tags", symbol: "tag") {
                NexusTagsPane(store: store)
            },
            SettingsPane("views", title: "Views", symbol: "square.grid.2x2") {
                NexusViewsPane(store: store, services: services)
            },
            SettingsPane("search", title: "Search", symbol: "magnifyingglass") {
                NexusSearchPane(store: store, services: services, index: index)
            },
            SettingsPane("appearance", title: "Appearance", symbol: "paintpalette") {
                AppearancePane(model: appearance, idPrefix: prefix)
            },
            SettingsPane("advanced", title: "Advanced", symbol: "slider.horizontal.3") {
                NexusAdvancedPane(store: store, services: services, update: update)
            },
        ]
        return SettingsWindowController(appName: "Nexus", idPrefix: prefix, theme: theme, panes: panes)
    }
}

private func settingID(_ suffix: String) -> String { "nexus.settings." + suffix }

// MARK: General

struct NexusGeneralPane: View {
    @ObservedObject var store: NexusPreferencesStore

    var body: some View {
        let prefs = store.current
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Windows") {
                SettingsPicker("New windows open to", detail: "Cmd+N, the Dock icon, and the first window at launch.",
                               id: settingID("general.newWindow"),
                               selection: binding(\.newWindowTarget),
                               options: NewWindowTarget.allCases.map { ($0, $0.title) })
                SettingsToggle("Open folders in tabs instead of new windows",
                               detail: "Several folders opened at once, and new windows, join the front window as tabs.",
                               id: settingID("general.tabs"), isOn: binding(\.openFoldersInTabs))
                    .help(prefs.openFoldersInTabs ? "On" : "Off")
            }
            SettingsSection("Keys", note: "Every other key keeps its Finder meaning.") {
                SettingsPicker("Return", id: settingID("general.return"), selection: binding(\.returnKey),
                               options: ReturnKeyAction.allCases.map { ($0, $0.title) })
            }
            SettingsSection("Window parts", note: "View › Show Path Bar and Show Status Bar change one window.") {
                SettingsToggle("Show the path bar", id: settingID("general.pathBar"), isOn: binding(\.showPathBar))
                SettingsToggle("Show the status bar", id: settingID("general.statusBar"), isOn: binding(\.showStatusBar))
            }
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<NexusPreferences, Value>) -> Binding<Value> {
        Binding(get: { store.current[keyPath: key] }, set: { value in store.update { $0[keyPath: key] = value } })
    }
}

// MARK: Sidebar

struct NexusSidebarPane: View {
    @ObservedObject var store: NexusPreferencesStore
    @ObservedObject var services: Services
    @ObservedObject var sidebar: SidebarModel

    var body: some View {
        let groups = sidebar.everything()
        let hidden = services.sidebarHidden
        let layout = store.current.sidebar
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Sections", note: "Turn a section off to hide it; the arrows set the order.") {
                ForEach(Array(layout.sectionOrder.enumerated()), id: \.element) { index, section in
                    let present = groups.contains { $0.section == section }
                    SettingsRow(section.title, detail: present ? nil : detail(for: section), symbol: section.symbol) {
                        HStack(spacing: 8) {
                            ReorderButtons(canMoveUp: index > 0, canMoveDown: index < layout.sectionOrder.count - 1) { offset in
                                store.update { $0.sidebar.move(section, by: offset) }
                            }
                            Toggle(section.title, isOn: Binding(
                                get: { !hidden.hides(section) },
                                set: { shown in setHidden { shown ? $0.show(section) : $0.hide(section) } }))
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                                .accessibilityIdentifier(settingID("sidebar.section.\(section.rawValue)"))
                                .accessibilityLabel("Show \(section.title)")
                        }
                    }
                }
            }
            ForEach(groups) { group in
                SettingsSection(group.section.title) {
                    let ids = group.items.map(\.id)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        SettingsRow(item.title, detail: item.folder.map { NexusSettingsFormat.abbreviate($0.path) }, symbol: item.symbol) {
                            HStack(spacing: 8) {
                                ReorderButtons(canMoveUp: index > 0, canMoveDown: index < ids.count - 1) { offset in
                                    store.update { $0.sidebar.move(item: item.id, in: group.section, by: offset, shown: ids) }
                                }
                                Toggle(item.title, isOn: Binding(
                                    get: { !hidden.hides(item) },
                                    set: { shown in setHidden { shown ? $0.show(item) : $0.hide(item) } }))
                                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                                    .accessibilityLabel("Show \(item.title)")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Show All in Sidebar") { services.showAllInSidebar() }
                    .disabled(hidden == SidebarHidden())
                    .accessibilityIdentifier(settingID("sidebar.showAll"))
                Button("Reset Order") { store.update { $0.sidebar = SidebarLayout(tags: $0.sidebar.tags, favouriteTags: $0.sidebar.favouriteTags) } }
                Spacer()
            }
            SettingsNote("File › Add to Sidebar (Ctrl+Cmd+T) adds a folder to Places. Projects come from settings.json.")
        }
    }

    private func detail(for section: SidebarSection) -> String {
        switch section {
        case .tags: return "Choose tags in the Tags pane."
        case .activeProjects: return "Set projectFolders in settings.json."
        case .savedSearches: return "Save a search with File › Save Search."
        default: return "Nothing to show here now."
        }
    }

    private func setHidden(_ change: (inout SidebarHidden) -> Void) {
        var next = services.sidebarHidden
        change(&next)
        services.setSidebarHidden(next)
    }
}

// MARK: Tags

struct NexusTagsPane: View {
    @ObservedObject var store: NexusPreferencesStore
    @Local private var newTag = ""

    var body: some View {
        let layout = store.current.sidebar
        let known = SidebarLayoutTags.known(layout)
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Tags", note: "Tags in the sidebar search the home folder for them. Favourites show as one-click chips in the inspector (Cmd+I).") {
                ForEach(known, id: \.self) { tag in
                    SettingsRow(tag, symbol: "tag") {
                        HStack(spacing: 14) {
                            Toggle("In sidebar", isOn: Binding(
                                get: { layout.tags.contains(tag) },
                                set: { on in store.update { $0.sidebar.setTag(tag, shown: on) } }))
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier(settingID("tags.sidebar.\(tag)"))
                            Toggle("Favourite", isOn: Binding(
                                get: { layout.favouriteTags.contains(tag) },
                                set: { on in store.update { $0.sidebar.setTag(tag, favourite: on) } }))
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier(settingID("tags.favourite.\(tag)"))
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            SettingsSection("Add a tag") {
                SettingsRow("Name") {
                    HStack(spacing: 8) {
                        TextField("Tag name", text: $newTag)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(add)
                            .accessibilityIdentifier(settingID("tags.new"))
                        Button("Add", action: add)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func add() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        store.update { $0.sidebar.setTag(tag, shown: true) }
        newTag = ""
    }
}

enum SidebarLayoutTags {
    /// Finder's colour tags, then any other tag chosen here.
    static func known(_ layout: SidebarLayout) -> [String] {
        var seen = Set<String>()
        return (SidebarLayout.standardTags + layout.tags + layout.favouriteTags).filter { seen.insert($0.lowercased()).inserted }
    }
}

// MARK: Views

struct NexusViewsPane: View {
    @ObservedObject var store: NexusPreferencesStore
    @ObservedObject var services: Services
    @ObservedObject var theme: ThemeStore

    init(store: NexusPreferencesStore, services: Services) {
        self.store = store
        self.services = services
        self.theme = services.theme
    }

    var body: some View {
        let defaults = services.viewPreferences.defaults
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Defaults", note: "For new windows and every folder without its own view (View › Remember View for This Folder keeps one).") {
                SettingsPicker("View", detail: "New windows open in it.", id: settingID("views.mode"),
                               selection: view(\.mode),
                               options: ViewMode.allCases.filter { $0 != .panes }.map { ($0, String($0.title.dropFirst(3)).capitalized) })
                SettingsPicker("Sort by", id: settingID("views.sort"), selection: Binding(
                    get: { defaults.sort.field },
                    set: { field in change { $0.sort = ItemSort(field: field, foldersFirst: $0.sort.foldersFirst, grouping: $0.sort.grouping) } }),
                    options: SortField.allCases.map { ($0, $0.title) })
                SettingsToggle("Keep folders on top", id: settingID("views.foldersFirst"), isOn: view(\.sort.foldersFirst))
                SettingsPicker("Group by", id: settingID("views.group"), selection: view(\.sort.grouping),
                               options: ItemGrouping.allCases.map { ($0, $0.title) })
                SettingsRow("Icon size", detail: "Icons and gallery thumbnails.") {
                    HStack(spacing: 8) {
                        Slider(value: view(\.iconSize), in: ViewSettings.iconSizes, step: 16)
                            .frame(width: 180)
                            .accessibilityIdentifier(settingID("views.iconSize"))
                        Text("\(Int(defaults.iconSize)) pt").font(.system(size: 12).monospacedDigit()).frame(width: 48, alignment: .trailing)
                    }
                }
            }
            SettingsSection("Kinds", note: "The theme's KIND_STYLE (\(theme.theme.kinds.style.rawValue)) and KIND_* colours.") {
                SettingsToggle("Show kind colours", detail: "File icons in the list take their kind's colour.",
                               id: settingID("views.kindColours"), isOn: Binding(
                                get: { store.current.showKindColours },
                                set: { on in store.update { $0.showKindColours = on } }))
                SettingsRow("Preview") {
                    HStack(spacing: 6) {
                        ForEach(FileKindName.allCases, id: \.self) { kind in
                            KindMark(style: theme.theme.kinds.style,
                                     color: store.current.showKindColours ? theme.theme.kinds[kind] : theme.theme.dim,
                                     label: KindLabel.short(kind), background: theme.theme.panel)
                                .help(kind.rawValue.capitalized)
                        }
                    }
                }
            }
        }
    }

    private func view<Value>(_ key: WritableKeyPath<ViewSettings, Value>) -> Binding<Value> {
        Binding(get: { services.viewPreferences.defaults[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
    }

    /// Saves the new defaults to view-settings.json and gives them to every
    /// pane still on the old ones.
    private func change(_ edit: (inout ViewSettings) -> Void) {
        let old = services.viewPreferences.defaults
        var next = old
        edit(&next)
        guard next != old else { return }
        services.viewPreferences.defaults = next
        services.saveViewPreferences()
        for model in WindowManager.shared.models {
            for pane in model.panes { pane.defaultsChanged(from: old, to: next) }
        }
    }
}

enum KindLabel {
    static func short(_ kind: FileKindName) -> String {
        switch kind {
        case .folder: return "DIR"
        case .document: return "DOC"
        case .pdf: return "PDF"
        case .presentation: return "PPT"
        case .spreadsheet: return "XLS"
        case .image: return "PNG"
        case .video: return "MOV"
        case .code: return "SWIFT"
        case .archive: return "ZIP"
        case .text: return "TXT"
        }
    }
}

// MARK: Search

struct NexusSearchPane: View {
    @ObservedObject var store: NexusPreferencesStore
    @ObservedObject var services: Services
    @ObservedObject var index: IndexStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Searching", note: "The chips under the search field widen a search from where it starts.") {
                SettingsPicker("Searches start in", id: settingID("search.scope"), selection: Binding(
                    get: { store.current.defaultSearchScope },
                    set: { value in store.update { $0.defaultSearchScope = value } }),
                    options: DefaultSearchScope.allCases.map { ($0, $0.title) })
                SettingsToggle("Include content matches", detail: "Files whose text matches, from Spotlight, below the name matches.",
                               id: settingID("search.content"), isOn: Binding(
                                get: { store.current.includeContentMatches },
                                set: { on in store.update { $0.includeContentMatches = on } }))
            }
            IndexStatusSection(model: index, idPrefix: NexusSettingsWindow.idPrefix, home: services.paths.home.path)
            SettingsSection("Saved searches", note: "\(services.savedSearches.names.count) saved. Each is also @name in any search.") {
                SettingsRow("saved-searches.tsv", detail: NexusSettingsFormat.abbreviate(services.paths.savedSearches.path)) {
                    Button("Open") { NexusSettingsFormat.openFile(services.paths.savedSearches) }
                }
            }
        }
    }
}

// MARK: Advanced

struct NexusAdvancedPane: View {
    @ObservedObject var store: NexusPreferencesStore
    @ObservedObject var services: Services
    @ObservedObject var update: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Files") {
                SettingsToggle("Show hidden files in new windows", detail: "Cmd+Shift+. switches one window.",
                               id: settingID("advanced.hidden"), isOn: binding(\.showHiddenFiles))
                SettingsToggle("Show all filename extensions", id: settingID("advanced.extensions"), isOn: binding(\.showAllExtensions))
                SettingsToggle("Warn before changing an extension", id: settingID("advanced.extensionWarning"),
                               isOn: binding(\.warnBeforeChangingExtension))
                SettingsToggle("Warn before emptying the Trash", detail: "Option+Shift+Cmd+Delete always empties without asking.",
                               id: settingID("advanced.trashWarning"), isOn: binding(\.warnBeforeEmptyingTrash))
            }
            SettingsSection("Configuration", note: "Places and projects are in settings.json; view exceptions and hidden sidebar items in Application Support.") {
                SettingsRow("Configuration folder", detail: NexusSettingsFormat.abbreviate(services.paths.settingsFolder.path)) {
                    Button("Open Configuration Folder") { FolderOpener.open(services.paths.settingsFolder) }
                        .accessibilityIdentifier(settingID("advanced.configFolder"))
                }
                SettingsRow("settings.json", detail: "Read again with Nexus › Reload Settings.") {
                    Button("Open") { NexusSettingsFormat.openSettingsFile(services) }
                }
            }
            UpdateSection(model: update, idPrefix: NexusSettingsWindow.idPrefix,
                          note: "Rebuilds Nexus, Sight and Iceberg from the package and reopens them.")
        }
    }

    private func binding(_ key: WritableKeyPath<NexusPreferences, Bool>) -> Binding<Bool> {
        Binding(get: { store.current[keyPath: key] }, set: { value in store.update { $0[keyPath: key] = value } })
    }
}

@MainActor
enum NexusSettingsFormat {
    static func abbreviate(_ path: String) -> String {
        let home = HomeFolder.url.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func openFile(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        NSWorkspace.shared.open(url)
    }

    static func openSettingsFile(_ services: Services) {
        let file = services.paths.settings
        if !FileManager.default.fileExists(atPath: file.path) {
            try? JSONFile<NexusSettings>(file).write(NexusSettings(places: nil, projectFolders: [], projects: []))
        }
        NSWorkspace.shared.open(file)
    }
}
