import AppKit
import BrowserKit
import FileKit
import IndexKit

/// Going places, the path bar (R5), views (R28) and sorting (R6, R7).
extension BrowserModel {
    func goHomeFolder(_ name: String) {
        focused.go(.folder(services.paths.home.appendingPathComponent(name, isDirectory: true)))
    }

    func goDrive() {
        guard let drive = GoogleDrive.accounts(home: services.paths.home).first else {
            Prompt.problem("Google Drive is not set up on this Mac.")
            return
        }
        focused.go(.folder(drive.myDrive))
    }

    /// Ctrl+Cmd+Up: the enclosing folder in a new window, with this one selected.
    func openEnclosingInNewWindow() {
        guard let parent = focused.location.parent, let folder = parent.location.folderURL else { return }
        WindowManager.shared.newWindow(at: folder, select: parent.select.map { [$0] } ?? [])
    }

    /// Finder's Network: the shares macOS automounts under /Network, or
    /// Connect to Server when there are none.
    func goNetwork() {
        let network = URL(fileURLWithPath: "/Network", isDirectory: true)
        guard FileManager.default.fileExists(atPath: network.path) else {
            connectToServer()
            return
        }
        focused.go(.folder(network))
    }

    var pathAliases: [String: URL] {
        guard let drive = GoogleDrive.accounts(home: services.paths.home).first else { return [:] }
        return ["Drive": drive.myDrive]
    }

    func beginPathEditing() {
        let folder = focused.location.diskFolder ?? services.paths.home
        pathText = PathSegments.editableText(for: folder, home: services.paths.home)
        editingPath = true
    }

    /// Return in the path field: a path goes there; a name goes to the best
    /// folder match from the index. Returns false to keep the field open.
    @discardableResult
    func commitPath(_ text: String, fuzzyMatch: URL?) -> Bool {
        let current = focused.location.diskFolder ?? services.paths.home
        switch PathInput.interpret(text, relativeTo: current, home: services.paths.home, aliases: pathAliases) {
        case .path(let url)?:
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return false }
            if isFolder.boolValue {
                focused.go(.folder(url))
            } else {
                focused.go(.folder(url.deletingLastPathComponent()), select: [url])
            }
        case .fuzzy?:
            guard let fuzzyMatch else { return false }
            focused.go(.folder(fuzzyMatch))
        case nil:
            break
        }
        editingPath = false
        return true
    }

    func completePath(_ text: String) -> String? {
        let current = focused.location.diskFolder ?? services.paths.home
        let options = PathInput.completions(
            for: text, relativeTo: current, home: services.paths.home, aliases: pathAliases, children: FolderReader.subfolderNames
        )
        guard let first = options.first else { return nil }
        return PathSegments.editableText(for: first, home: services.paths.home) + "/"
    }

    /// Folder names from the index for Go to Folder.
    func folderMatches(_ text: String) async -> [URL] {
        let matches = await services.index.search(text, limit: 60)
        return matches.filter(\.isFolder).prefix(8).map { URL(fileURLWithPath: $0.path, isDirectory: true) }
    }

    // MARK: Views

    func setMode(for command: BrowserCommand) {
        let number: Int
        switch command {
        case .viewIcons: number = 1
        case .viewList: number = 2
        case .viewColumns: number = 3
        case .viewGallery: number = 4
        default: number = 5
        }
        guard let new = ViewMode.numbered(number) else { return }
        mode = new
        if new == .panes, layout.count == 1 { setPaneCount(2) }
        if new == .columns { focused.columnRoot = focused.location.folderURL }
        var settings = focused.state.settings
        settings.mode = new
        focused.setSettings(settings)
    }

    func sort(by command: BrowserCommand) {
        let fields: [BrowserCommand: SortField] = [
            .sortName: .name, .sortKind: .kind, .sortLastOpened: .lastOpened, .sortAdded: .added,
            .sortModified: .modified, .sortCreated: .created, .sortSize: .size, .sortTags: .tags, .sortManual: .manual,
        ]
        guard let field = fields[command] else { return }
        sort(focused, by: field)
    }

    func sort(_ pane: PaneModel, by field: SortField) {
        var settings = pane.state.settings
        settings.sort = settings.sort.clicking(field)
        pane.setSettings(settings)
    }

    /// View › Keep Folders on Top, on top of whatever the sort is.
    func toggleFoldersOnTop() {
        var settings = focused.state.settings
        settings.sort.foldersFirst.toggle()
        focused.setSettings(settings)
    }

    /// View › Group By: rows gathered by kind, each group in the current sort.
    func group(by grouping: ItemGrouping) {
        var settings = focused.state.settings
        settings.sort.grouping = grouping
        focused.setSettings(settings)
    }

    func scaleIcons(by factor: Double) {
        var settings = focused.state.settings
        let range = ViewSettings.iconSizes
        settings.iconSize = min(range.upperBound, max(range.lowerBound, (settings.iconSize * factor).rounded()))
        focused.setSettings(settings)
    }

    func rememberView() {
        guard let folder = focused.location.folderURL else { return }
        var settings = focused.state.settings
        settings.mode = mode
        services.viewPreferences.remember(settings, for: folder.path)
        services.saveViewPreferences()
    }

    func useAsDefaultView() {
        var settings = focused.state.settings
        settings.mode = mode
        services.viewPreferences.defaults = settings
        if let folder = focused.location.folderURL { services.viewPreferences.forget(folder.path) }
        services.saveViewPreferences()
    }

    func toggleHidden() {
        showHidden.toggle()
        for pane in panes {
            pane.showHidden = showHidden
            pane.reload()
        }
    }

    // MARK: Search

    func search(_ text: String, scope: SearchScope?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            endSearch()
            return
        }
        let start = scope ?? currentSearchScope ?? (focused.location.folderURL.map { .folder($0.path) } ?? .home)
        // Typing more refines the search in place rather than adding history.
        if case .search = focused.location {
            focused.replace(.search(query: trimmed, scope: start))
        } else {
            focused.go(.search(query: trimmed, scope: start))
        }
    }

    var currentSearchScope: SearchScope? {
        if case .search(_, let scope) = focused.location { return scope }
        return nil
    }

    func endSearch() {
        searchText = ""
        if case .search = focused.location { focused.back() }
    }

    func saveSearch() {
        guard case .search(let query, _) = focused.location,
              let name = Prompt.text("Save Search", message: "It appears in the sidebar and as @name in any search.", action: "Save")
        else { return }
        services.savedSearches.save(name, query: query)
        services.saveSearches()
    }

    func runSavedSearch(_ name: String) {
        guard let query = services.savedSearches.query(named: name) else { return }
        searchText = query
        focused.go(.search(query: query, scope: .home))
    }
}
