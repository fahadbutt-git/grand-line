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

    /// Shift+Cmd+G: Finder's Go to Folder, in the path bar's field.
    func beginPathEditing() {
        let folder = focused.location.diskFolder ?? services.paths.home
        omnibarOrigin = .goToFolder
        pathText = PathSegments.editableText(for: folder, home: services.paths.home)
        pathProblem = nil
        editingPath = true
    }

    func endPathEditing() {
        editingPath = false
        pathProblem = nil
    }

    /// Return in the path field: a path goes there; a name goes to the folder
    /// picked in the list, a folder of that name nearby, or the best folder
    /// match from the index. When nothing is found the field stays open and
    /// says so under it.
    func submitPath(_ text: String, fuzzyMatch: URL?) {
        let home = services.paths.home
        let current = focused.location.diskFolder ?? home
        guard let intent = PathInput.interpret(text, relativeTo: current, home: home, aliases: pathAliases) else {
            endPathEditing()
            return
        }
        switch intent {
        case .path(let url):
            if !go(to: url) { showPathProblem(PathInput.notFound(intent, home: home)) }
        case .fuzzy(let name):
            if let fuzzyMatch, go(to: fuzzyMatch) { return }
            if let near = PathInput.nearbyFolder(named: name, in: current, home: home, isFolder: Self.isFolder), go(to: near) { return }
            // The list under the field may not have its answer yet: ask the index now.
            Task { [weak self] in
                guard let self else { return }
                let found = await self.folderMatches(name).first
                guard self.editingPath, self.pathText == text else { return }
                if let found, self.go(to: found) { return }
                self.showPathProblem(PathInput.notFound(intent, home: home))
            }
        }
    }

    /// Goes to a folder, or to a file's folder with the file selected.
    private func go(to url: URL) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { return false }
        if isFolder.boolValue {
            focused.go(.folder(url))
        } else {
            focused.go(.folder(url.deletingLastPathComponent()), select: [url])
        }
        endPathEditing()
        return true
    }

    private func showPathProblem(_ text: String) {
        pathProblem = text
        NSSound.beep()
    }

    nonisolated private static func isFolder(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// Tab: the one matching folder, or as much as the matches share.
    func completePath(_ text: String) -> String? {
        let home = services.paths.home
        return PathInput.complete(text, options: pathCompletions(text)) { PathSegments.editableText(for: $0, home: home) }
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
        choose(focused, sort: field)
    }

    /// A column header clicked: the same column flips its direction (Finder).
    func sort(_ pane: PaneModel, by field: SortField) {
        var settings = pane.state.settings
        settings.sort = settings.sort.clicking(field)
        pane.setSettings(settings)
    }

    /// View › Sort By, its shortcut or View Options: the field in its default direction.
    func choose(_ pane: PaneModel, sort field: SortField) {
        var settings = pane.state.settings
        settings.sort = settings.sort.choosing(field)
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
        let start = scope ?? currentSearchScope
            ?? NexusPreferencesStore.shared.current.defaultSearchScope.scope(folder: focused.location.folderURL)
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

    /// Saves the query with where it looks and how its results show: the
    /// scope, the list's columns, the sort and the grouping.
    func saveSearch() {
        guard case .search(let query, let scope) = focused.location,
              let name = Prompt.text("Save Search", message: "It appears in the sidebar and as @name in any search. Its scope, columns, sort and grouping are kept with it.", action: "Save")
        else { return }
        let settings = focused.state.settings
        services.savedSearches.save(SavedSearch(name: name, query: query, scope: scope, columns: settings.columns, sort: settings.sort))
        services.saveSearches()
    }

    func runSavedSearch(_ name: String) {
        guard let saved = services.savedSearches.search(named: name) else { return }
        searchText = saved.query
        focused.go(.search(query: saved.query, scope: saved.runScope))
        guard saved.columns != nil || saved.sort != nil else { return }
        var settings = focused.state.settings
        if let columns = saved.columns { settings.columns = columns }
        if let sort = saved.sort { settings.sort = sort }
        focused.showTransiently(settings)
    }

    /// View › Show Contents of Subfolders: the folder flat, from the index.
    func toggleFlatView() {
        guard focused.location.folderURL != nil else { return }
        focused.setFlat(!focused.state.isFlat)
    }
}
