import AppKit
import BrowserKit
import FileKit
import IndexKit

/// What every window shares: file operations and their undo, sizes, recents,
/// the name index, stored view settings, workspaces, saved searches and the
/// Open With table.
@MainActor
final class Services: ObservableObject {
    static let shared = Services()

    let paths = AppPaths()
    let operations = FileOperations()
    let folderSizes = FolderSize()
    let recents = Recents()
    let index: FileIndex
    let selectionFile: SelectionFile
    let workspaces: WorkspaceStore
    let theme = ThemeStore()
    lazy var sidebar = SidebarModel(services: self)

    @Published var viewPreferences: ViewPreferences
    @Published var savedSearches: SavedSearches
    @Published private(set) var defaultApps: DefaultAppsTable
    @Published private(set) var settings: NexusSettings
    @Published var clipboard = FileClipboard()
    @Published private(set) var transfers = TransferList()
    @Published private(set) var undoTitle: String?
    @Published private(set) var redoTitle: String?
    @Published private(set) var sidebarHidden: SidebarHidden
    private(set) var trashLedger: TrashLedger
    private(set) var drives: [GoogleDrive]

    private init() {
        let order = ScanOrder.home(paths.home.path)
        index = (try? FileIndex.load(from: paths.nameIndex, order: order)) ?? FileIndex(roots: [paths.home.path], order: order)
        selectionFile = SelectionFile(url: paths.selectionFile)
        workspaces = WorkspaceStore(folder: paths.workspaces)
        viewPreferences = JSONFile<ViewPreferences>(paths.viewPreferences).read() ?? ViewPreferences()
        savedSearches = SavedSearches.load(paths.savedSearches)
        defaultApps = DefaultAppsTable.load(paths.defaultApps)
        settings = NexusSettings.load(paths.settings)
        trashLedger = JSONFile<TrashLedger>(paths.trashLedger).read() ?? TrashLedger()
        sidebarHidden = JSONFile<SidebarHidden>(paths.sidebarHidden).read() ?? SidebarHidden()
        drives = GoogleDrive.accounts(home: paths.home)
        trashLedger.prune { FileManager.default.fileExists(atPath: $0) }
    }

    func start() {
        let index = self.index
        let file = paths.nameIndex
        Task {
            // Searchable while it builds; saved along the way and when done.
            let count = await index.count
            let complete = await index.isComplete
            if count == 0 || !complete { await index.build(savingTo: file, every: 30) }
            await index.startWatching()
        }
        let progress = operations.progress
        Task { [weak self] in
            for await step in progress { self?.transfers.apply(step) }
        }
        theme.start()
        sidebar.start()
    }

    func stop() {
        let index = self.index
        let file = paths.nameIndex
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            try? await index.save(to: file)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
    }

    // MARK: Stored state

    func saveViewPreferences() {
        try? JSONFile<ViewPreferences>(paths.viewPreferences).write(viewPreferences)
    }

    func saveSearches() {
        try? savedSearches.write(to: paths.savedSearches)
        sidebar.refresh()
    }

    func reloadConfig() {
        defaultApps = DefaultAppsTable.load(paths.defaultApps)
        settings = NexusSettings.load(paths.settings)
        savedSearches = SavedSearches.load(paths.savedSearches)
        drives = GoogleDrive.accounts(home: paths.home)
        sidebar.refresh()
    }

    /// Add to Sidebar: the folder joins Places in settings.json.
    func addPlace(_ folder: URL) {
        let home = paths.home
        let current = settings.placeURLs(home: home) ?? SidebarBuilder.defaultPlaces(home: home, drives: drives)
        writeSettings(settings.addingPlace(folder, current: current, home: home))
    }

    /// Remove from Sidebar: a place leaves settings.json; a saved search and a
    /// built-in item are hidden, so a saved search still works as @name.
    func removeFromSidebar(_ item: SidebarItem) {
        switch (item.removal, item.target) {
        case (.remove, _):
            guard let folder = item.folder else { return }
            let home = paths.home
            let current = settings.placeURLs(home: home) ?? SidebarBuilder.defaultPlaces(home: home, drives: drives)
            writeSettings(settings.removingPlace(folder, current: current, home: home))
        case (.hide, _):
            sidebarHidden.hide(item)
            saveSidebarHidden()
        }
    }

    func hideSection(_ section: SidebarSection) {
        sidebarHidden.hide(section)
        saveSidebarHidden()
    }

    func showAllInSidebar() {
        sidebarHidden = SidebarHidden()
        saveSidebarHidden()
    }

    private func saveSidebarHidden() {
        try? JSONFile<SidebarHidden>(paths.sidebarHidden).write(sidebarHidden)
        sidebar.refresh()
    }

    private func writeSettings(_ updated: NexusSettings) {
        guard updated != settings else { return }
        do {
            try JSONFile<NexusSettings>(paths.settings).write(updated)
            settings = updated
            sidebar.refresh()
        } catch {
            Prompt.problem("The sidebar could not be changed.", error)
        }
    }

    // MARK: Trash

    func noteTrashed(_ originals: [URL], to trashed: [URL]) {
        trashLedger.record(originals: originals, trashed: trashed)
        try? JSONFile<TrashLedger>(paths.trashLedger).write(trashLedger)
    }

    func notePutBack(_ trashed: URL) {
        trashLedger.forget(trashed)
        try? JSONFile<TrashLedger>(paths.trashLedger).write(trashLedger)
    }

    // MARK: Undo

    /// Called after every operation, so the Edit menu says "Undo Copy" and "Redo Move".
    func refreshUndo() {
        let operations = self.operations
        Task { [weak self] in
            let undo = await operations.undoKind
            let redo = await operations.redoKind
            self?.undoTitle = undo.map { "Undo " + $0.rawValue }
            self?.redoTitle = redo.map { "Redo " + $0.rawValue }
        }
    }

    // MARK: Opening

    func noteOpened(_ urls: [URL]) {
        let recents = self.recents
        let index = self.index
        Task {
            for url in urls {
                try? await recents.record(url)
                await index.noteOpened(url.path)
            }
        }
    }
}
