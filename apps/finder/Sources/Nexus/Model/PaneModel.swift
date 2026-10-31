import AppKit
import ArchiveKit
import BrowserKit
import FileKit
import IndexKit

/// One pane on screen: loads its place, keeps it current with FSEvents, and
/// measures folder sizes in the background (R9).
@MainActor
final class PaneModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var state: PaneState
    @Published private(set) var badges: [String: DriveBadge] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var problem: String?
    @Published private(set) var freeSpace: Int64?
    /// Where the column view starts; follows the pane when it leaves.
    @Published var columnRoot: URL?
    private(set) var listing: ArchiveListing?
    var showHidden = false
    var onSelectionChange: (() -> Void)?

    private unowned let services: Services
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var search: SearchRunner?
    /// The window's setting, used in every folder without an exception (R6).
    private var windowSettings: ViewSettings

    init(location: BrowserLocation, settings: ViewSettings, services: Services) {
        self.services = services
        self.windowSettings = settings
        self.state = PaneState(location: location, settings: settings)
    }

    var location: BrowserLocation { state.location }
    var items: [FileItem] { state.items }
    var selectedItems: [FileItem] { state.selectedItems }
    var inTrash: Bool { location.folderURL?.standardizedFileURL == services.paths.trash.standardizedFileURL }

    // MARK: Navigation

    func go(_ location: BrowserLocation, select: [URL] = []) {
        state.navigate(to: location, select: select)
        applyFolderSettings()
        reload()
    }

    func replace(_ location: BrowserLocation) {
        state.replace(with: location)
        reload()
    }

    func back() {
        if state.goBack() { applyFolderSettings(); reload() }
    }

    func forward() {
        if state.goForward() { applyFolderSettings(); reload() }
    }

    func up() {
        if state.goUp() { applyFolderSettings(); reload() }
    }

    /// A folder with its own stored view uses it (R6).
    private func applyFolderSettings() {
        guard let folder = location.folderURL else { return }
        let prefs = services.viewPreferences
        state.setSettings(prefs.settings(for: folder.path, window: windowSettings))
        state.setManualOrder(prefs.manualOrder(for: folder.path))
    }

    /// Settings, Views changed the defaults: a pane still on the old ones takes the new ones.
    func defaultsChanged(from old: ViewSettings, to new: ViewSettings) {
        var listOld = old
        listOld.mode = .list
        guard windowSettings == listOld || windowSettings == old else { return }
        var next = new
        next.mode = .list
        windowSettings = next
        applyFolderSettings()
        readLastOpened()
    }

    func setSettings(_ settings: ViewSettings) {
        state.setSettings(settings)
        readLastOpened()
        if let folder = location.folderURL, services.viewPreferences.change(settings, in: folder.path) {
            services.saveViewPreferences()
        } else {
            windowSettings = settings
        }
    }

    // MARK: Selection

    func select(ids: [String]) {
        state.selection.set(ids, in: state.ids)
        onSelectionChange?()
    }

    func updateSelection(_ change: (inout SelectionModel, [String]) -> Void) {
        change(&state.selection, state.ids)
        onSelectionChange?()
    }

    func moveManually(_ names: [String], to index: Int) {
        let order = state.moveManually(names, to: index)
        guard let folder = location.folderURL else { return }
        services.viewPreferences.setManualOrder(order, for: folder.path)
        if !services.viewPreferences.hasException(folder.path) {
            services.viewPreferences.remember(state.settings, for: folder.path)
        }
        services.saveViewPreferences()
    }

    // MARK: Loading

    func reload() {
        loadTask?.cancel()
        search?.stop()
        problem = nil
        isLoading = true
        switch location {
        case .folder(let url):
            watch(url)
            loadFolder(url)
            services.sidebar.visited(url)
        case .archive(let url, let entry):
            stopWatching()
            loadArchive(url, entry: entry)
        case .search(let text, let scope):
            stopWatching()
            runSearch(text, scope: scope)
        case .recents:
            stopWatching()
            loadRecents()
        }
    }

    private func finish(_ items: [FileItem]) {
        state.load(items)
        state.applyPendingSelection()
        isLoading = false
        onSelectionChange?()
        readLastOpened()
    }

    /// Spotlight's last-opened dates, read in the background and only while the
    /// pane sorts by them (one Spotlight lookup per item).
    private func readLastOpened() {
        guard state.settings.sort.field == .lastOpened else { return }
        let known = state.lastOpened
        let urls = state.items.filter { !$0.isInArchive && known[$0.path] == nil }.map(\.url)
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            let dates = await Task.detached(priority: .utility) { LastOpened.dates(for: urls) }.value
            self?.state.setLastOpened(dates)
        }
    }

    private func loadFolder(_ url: URL) {
        let hidden = showHidden
        let drives = GoogleDrive.accounts(home: services.paths.home)
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<([FileItem], [String: DriveBadge]), Error> in
                do {
                    let items = try FolderReader.items(in: url, showHidden: hidden)
                    var badges: [String: DriveBadge] = [:]
                    if drives.contains(where: { $0.contains(url) }) {
                        for item in items { badges[item.id] = DriveBadge.read(item.url, drives: drives) }
                    }
                    return .success((items, badges))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let (items, badges)):
                self.badges = badges
                self.finish(items)
                self.freeSpace = VolumeInfo.containing(url)?.availableBytes
                self.measureSizes()
            case .failure(let error):
                self.problem = error.localizedDescription
                self.finish([])
            }
        }
    }

    private func loadArchive(_ url: URL, entry: String) {
        loadTask = Task { [weak self] in
            let known = self?.listing?.archive == url ? self?.listing : nil
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ArchiveListing, Error> in
                if let known { return .success(known) }
                return Result { try Archive.list(url) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let listing):
                self.listing = listing
                self.badges = [:]
                self.finish(ArchiveRows.items(in: listing, at: entry) ?? [])
            case .failure(let error):
                self.problem = "This archive could not be read. " + error.localizedDescription
                self.finish([])
            }
        }
    }

    private func loadRecents() {
        let recents = services.recents
        loadTask = Task { [weak self] in
            let list = await recents.list()
            let items = list.compactMap { FileItem.read($0.url) }
            guard let self, !Task.isCancelled else { return }
            var sort = self.state.settings
            sort.sort = ItemSort(field: .modified, foldersFirst: false)
            self.state.setSettings(sort)
            self.finish(items)
        }
    }

    private func runSearch(_ text: String, scope: SearchScope) {
        let runner = SearchRunner(services: services)
        search = runner
        runner.start(text, scope: scope) { [weak self] paths in
            let items = paths.compactMap { FileItem.read(URL(fileURLWithPath: $0)) }
            self?.finish(items)
        }
    }

    /// Cached sizes come back at once; the rest arrive one by one.
    private func measureSizes() {
        sizeTask?.cancel()
        let folders = state.items.filter(\.isFolder).map(\.url)
        let sizes = services.folderSizes
        sizeTask = Task { [weak self] in
            for url in folders {
                if Task.isCancelled { return }
                let result = await sizes.size(of: url)
                self?.state.setSize(result.bytes, for: url.path)
            }
        }
    }

    // MARK: Watching

    private func watch(_ folder: URL) {
        if watcher?.paths == [folder.path] { return }
        stopWatching()
        let watcher = FolderWatcher(paths: [folder.path], latency: 0.3)
        guard watcher.start() else { return }
        self.watcher = watcher
        let changes = watcher.changes
        let sizes = services.folderSizes
        watchTask = Task { [weak self] in
            for await batch in changes {
                await sizes.invalidate(batch)
                self?.changed(batch, in: folder)
            }
        }
    }

    private func changed(_ batch: [FolderChange], in folder: URL) {
        let real = FolderWatcher.realPath(folder.path)
        let direct = batch.contains { $0.path == real || $0.recursive }
        if direct, location.folderURL == folder {
            loadFolder(folder)
        } else {
            measureSizes()
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }

    func tearDown() {
        stopWatching()
        loadTask?.cancel()
        sizeTask?.cancel()
        search?.stop()
    }
}
