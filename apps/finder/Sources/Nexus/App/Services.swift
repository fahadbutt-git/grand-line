import AppKit
import ArchiveKit
import BrowserKit
import FileKit
import IndexKit
import IndexService

/// What every window shares: file operations, the task engine that runs them
/// and their undo, sizes, recents, the name index, stored view settings,
/// workspaces, saved searches and the Open With table.
@MainActor
final class Services: ObservableObject {
    static let shared = Services()

    let paths = AppPaths()
    let operations: FileOperations
    /// Every file operation runs here as a task: in order, cancellable, with progress.
    let tasks: FileTaskQueue
    let folderSizes = FolderSize()
    let recents = Recents()
    /// File names, from the Grand Line Index service Sight shares.
    let index: SharedIndexClient
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
    /// What Undo can reverse, newest first, for the tasks popover.
    @Published private(set) var undoHistory: [OperationRecord] = []
    @Published private(set) var sidebarHidden: SidebarHidden
    private(set) var trashLedger: TrashLedger
    private(set) var drives: [GoogleDrive]

    private init() {
        let operations = FileOperations()
        self.operations = operations
        tasks = FileTaskQueue(operations: operations)
        index = SharedIndexClient(home: paths.home.path)
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
        // Saved searches from before scopes and columns were kept: written
        // once in the new form, each with the home folder it always used.
        if savedSearches.isLegacy { try? savedSearches.write(to: paths.savedSearches) }
    }

    func start() {
        // The service keeps the index current; this only connects (or, while
        // it is out of reach, reads its snapshot).
        index.start()
        let progress = operations.progress
        Task { [weak self] in
            for await step in progress { self?.transfers.apply(step) }
        }
        let events = tasks.events
        Task { [weak self] in
            for await event in events {
                self?.transfers.apply(event)
                if event.state.isDone { self?.refreshUndo() }
            }
        }
        // Quick Look's copies of archive items from an earlier run (security note L2).
        Task.detached(priority: .utility) { Archive.TemporaryFolder.cleanAtLaunch() }
        theme.start()
        sidebar.start()
    }

    /// The service saves the index, so quitting waits for nothing.
    func stop() {
        index.stop()
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

    /// Settings, Sidebar: shows or hides sections and items.
    func setSidebarHidden(_ hidden: SidebarHidden) {
        guard hidden != sidebarHidden else { return }
        sidebarHidden = hidden
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
            let history = await operations.history
            self?.undoTitle = undo.map { "Undo " + $0.rawValue }
            self?.redoTitle = redo.map { "Redo " + $0.rawValue }
            self?.undoHistory = history
        }
    }

    // MARK: Tasks

    /// Runs file work as a task after the others; returns what it made.
    func run(_ kind: FileOperationKind?, _ title: String,
             _ body: @escaping @Sendable (FileOperations) async throws -> [URL]) async throws -> [URL] {
        try await tasks.run(kind, title: title, body: body)
    }

    func cancelTask(_ id: FileTaskID) {
        transfers.markCancelling(id)
        let tasks = self.tasks
        Task { await tasks.cancel(id) }
    }

    func clearEndedTasks() {
        transfers.clearEnded()
    }

    // MARK: Opening

    func noteOpened(_ urls: [URL]) {
        let recents = self.recents
        let index = self.index
        for url in urls { index.noteOpened(url.path) }
        Task {
            for url in urls { try? await recents.record(url) }
        }
    }
}
