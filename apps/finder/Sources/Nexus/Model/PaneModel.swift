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
    /// A folder read is in flight; changes meanwhile ask for one more after it.
    private var reading = false
    private var readAgain = false
    /// The rows the list has on screen, for folder sizes.
    private var visibleIDs: Set<String> = []
    /// A new folder whose name is edited once it shows, selected.
    private var renameOnShow: (url: URL, begin: () -> Void)?
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
        let bySize = settings.sort.field == .size && state.settings.sort.field != .size
        state.setSettings(settings)
        readLastOpened()
        // Sorting by size needs every folder's size, not only those on screen.
        if bySize { measureSizes() }
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

    /// A saved search's own columns and sort, for its results only: the
    /// window's settings stay as they are for the folders you go to next.
    func showTransiently(_ settings: ViewSettings) {
        state.setSettings(settings)
        readLastOpened()
    }

    /// The omnibar's filter: rows narrow as you type.
    func setFilter(_ text: String) {
        state.setFilter(text)
        onSelectionChange?()
    }

    /// Flat view: the folder and everything below it, or back to the folder.
    func setFlat(_ on: Bool) {
        guard state.isFlat != on else { return }
        state.isFlat = on
        reload()
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
        reading = false
        readAgain = false
        search?.stop()
        problem = nil
        isLoading = true
        switch location {
        case .folder(let url):
            watch(url)
            if state.isFlat { loadFlat(url) } else { loadFolder(url) }
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
        // Only the load that follows the task: if the item is not the one
        // selected then (the pane went elsewhere), the rename is dropped.
        if let wanted = renameOnShow {
            renameOnShow = nil
            if state.selectedItems.count == 1, state.selectedItems[0].url.standardizedFileURL == wanted.url.standardizedFileURL {
                wanted.begin()
            }
        }
    }

    /// Calls `begin` once `url` is listed here and is the one item selected
    /// (a new folder after its task), so its name, and no other, is edited.
    func renameWhenShown(_ url: URL, begin: @escaping () -> Void) {
        renameOnShow = (url, begin)
        if state.selectedItems.count == 1, state.selectedItems[0].url.standardizedFileURL == url.standardizedFileURL {
            renameOnShow = nil
            begin()
        }
    }

    /// Work off the main thread that stops when the task awaiting it is
    /// cancelled (`FolderReader` checks as it reads).
    nonisolated static func offMain<T: Sendable>(priority: TaskPriority = .userInitiated,
                                                 _ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: priority) { try work() }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
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
        reading = true
        loadTask = Task { [weak self] in
            let result: Result<([FileItem], [String: DriveBadge], Int64?), Error>
            do {
                result = .success(try await Self.offMain { () -> ([FileItem], [String: DriveBadge], Int64?) in
                    let items = try FolderReader.items(in: url, showHidden: hidden)
                    var badges: [String: DriveBadge] = [:]
                    if drives.contains(where: { $0.contains(url) }) {
                        for item in items { badges[item.id] = DriveBadge.read(item.url, drives: drives) }
                    }
                    return (items, badges, VolumeInfo.containing(url)?.availableBytes)
                })
            } catch is CancellationError {
                return
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.reading = false
            switch result {
            case .success(let (items, badges, free)):
                self.badges = badges
                self.finish(items)
                self.freeSpace = free
                self.measureSizes()
                if self.inTrash { self.services.refreshFinderPutBack() }
            case .failure(let error):
                self.problem = error.localizedDescription
                self.finish([])
            }
            self.readAgainIfAsked()
        }
    }

    /// Changes on disk while a read was in flight: one more read after it, never
    /// a pile of reads running at once.
    private func readAgainIfAsked() {
        guard readAgain, case .folder(let url) = location else { return }
        readAgain = false
        if state.isFlat { loadFlat(url) } else { loadFolder(url) }
    }

    /// A change on disk: read again now, or once the read in flight ends.
    private func refresh(_ url: URL) {
        if reading {
            readAgain = true
        } else if state.isFlat {
            loadFlat(url)
        } else {
            loadFolder(url)
        }
    }

    /// Flat view: names from the shared index, scoped to the folder, read from
    /// disk where the index does not look (`FlatListing`).
    private func loadFlat(_ url: URL) {
        let hidden = showHidden
        let home = services.paths.home.path
        let index = services.index
        let folder = url.standardizedFileURL.path
        reading = true
        loadTask = Task { [weak self] in
            var indexed: [String] = []
            if !FlatListing.needsDisk(folder, home: home) {
                let batches = await withTaskGroup(of: [String].self) { group -> [[String]] in
                    for probe in FlatListing.probes {
                        group.addTask { await index.search(probe, limit: FlatListing.limit, scope: [folder]).map(\.path) }
                    }
                    var all: [[String]] = []
                    for await batch in group { all.append(batch) }
                    return all
                }
                indexed = FlatListing.merge(batches, under: folder, home: home, showHidden: hidden)
            }
            // An index still building (or a folder it skips) is read from disk.
            let found = indexed
            let readItems: @Sendable () throws -> [FileItem] = {
                let paths = found.isEmpty ? FlatListing.walk(url, home: home, showHidden: hidden) : found
                var read: [FileItem] = []
                for (i, path) in paths.enumerated() {
                    if i & 511 == 0 { try Task.checkCancellation() }
                    if let item = FileItem.read(URL(fileURLWithPath: path)) { read.append(item) }
                }
                return read
            }
            guard let items = try? await Self.offMain(readItems) else { return }
            guard let self, !Task.isCancelled else { return }
            self.reading = false
            self.badges = [:]
            self.finish(items)
            self.freeSpace = VolumeInfo.containing(url)?.availableBytes
            self.readAgainIfAsked()
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

    /// The list's rows on screen changed (a scroll, a resize): folders that
    /// came into view get their sizes.
    func setVisible(_ ids: [String]) {
        let shown = Set(ids)
        guard shown != visibleIDs else { return }
        let added = shown.subtracting(visibleIDs)
        visibleIDs = shown
        let unmeasured = state.items.contains { $0.isFolder && added.contains($0.id) && state.folderSizes[$0.path] == nil }
        if unmeasured { measureSizes(after: 0.15) }
    }

    /// Cached sizes come back at once; the rest arrive one by one.
    /// Measures the folders on screen (all of them when sorted by size), as
    /// Settings' "Calculate folder sizes" allows: never past their volume,
    /// network and cloud folders only when chosen, within
    /// `FolderSizeLimits.listing`, and a new place or a new set of rows
    /// cancels the walk at once. `after` waits first, so a stream of changes
    /// deep inside them (an app writing its caches below the home folder)
    /// measures once when it calms down, not on every event.
    private func measureSizes(after delay: TimeInterval = 0) {
        sizeTask?.cancel()
        let prefs = NexusPreferencesStore.shared.current
        guard prefs.calculateFolderSizes, case .folder = location, !state.isFlat else { return }
        let folders = SizeScope.folders(state.items, visible: visibleIDs, sortedBySize: state.settings.sort.field == .size)
        guard !folders.isEmpty else { return }
        let limits = prefs.folderSizeLimits
        let sizes = services.folderSizes
        sizeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
            }
            for url in folders {
                if Task.isCancelled { return }
                guard let result = await sizes.size(of: url, limits: limits) else { continue }
                if Task.isCancelled { return }
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
        if state.isFlat, location.folderURL == folder, !batch.isEmpty {
            refresh(folder)
        } else if direct, location.folderURL == folder {
            refresh(folder)
        } else {
            measureSizes(after: Self.deepChangeDelay)
        }
    }

    /// How long sizes wait after a change below the folders shown.
    static let deepChangeDelay: TimeInterval = 2

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }

    func tearDown() {
        stopWatching()
        loadTask?.cancel()
        reading = false
        sizeTask?.cancel()
        search?.stop()
    }
}
