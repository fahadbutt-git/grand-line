import AppKit
import AppRuntime
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
    /// Present while a file task runs, so the unattended update waits to
    /// swap Nexus (lib/auto-update.sh).
    let busy = BusyMarker(name: "nexus")
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
    /// Finder's own Put Back records for the Trash (its .DS_Store), for items
    /// Nexus did not trash; read in the background when the Trash is shown.
    private(set) var finderPutBack: [String: URL] = [:]
    private var ledgerSave: Task<Void, Never>?
    /// The progress not yet shown: the tasks popover takes at most ten
    /// updates a second, however fast files are copied.
    private var pendingProgress: OperationProgress?
    private var progressFlush: Task<Void, Never>?
    private var lastProgress = Date.distantPast
    static let progressInterval: TimeInterval = 0.1
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
        // Clipboard and task events, for a paste that made nothing (nexus.log).
        NexusLog.start(file: NexusLog.file(home: paths.home))
        NexusLog.note("Nexus started (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
        // The service keeps the index current; this only connects (or, while
        // it is out of reach, reads its snapshot).
        index.start()
        let progress = operations.progress
        Task { [weak self] in
            for await step in progress { self?.progressArrived(step) }
        }
        // Every item FileOperations sends to the Trash, or takes out, as it
        // happens: Put Back knows a task's items even when it stopped halfway.
        let trashChanges = operations.trashChanges
        Task { [weak self] in
            for await change in trashChanges { self?.trashChanged(change) }
        }
        let events = tasks.events
        Task { [weak self] in
            for await event in events {
                NexusLog.note("task \(event.id.value) \(Services.describe(event.state)): \(event.title)")
                self?.transfers.apply(event)
                self?.busy.set("task \(event.id.value)", busy: !event.state.isDone)
                if event.state.isDone { self?.refreshUndo() }
            }
        }
        // Quick Look's copies of archive items from an earlier run (security
        // note L2); a copy someone edited goes to the Trash, not away.
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

    private func trashChanged(_ change: TrashChange) {
        trashLedger.apply(change)
        // One write for a burst (500 items trashed), a moment after the last.
        guard ledgerSave == nil else { return }
        ledgerSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            self.ledgerSave = nil
            let ledger = self.trashLedger
            let file = JSONFile<TrashLedger>(self.paths.trashLedger)
            await Task.detached(priority: .utility) { try? file.write(ledger) }.value
        }
    }

    /// Where Put Back sends an item in the Trash: Nexus's ledger first, then
    /// Finder's own record of it.
    func putBackOriginal(of trashed: URL) -> URL? {
        trashLedger.original(of: trashed) ?? finderPutBack[trashed.standardizedFileURL.path]
    }

    func canPutBack(_ items: [URL]) -> Bool {
        !items.isEmpty && items.allSatisfy { putBackOriginal(of: $0) != nil }
    }

    /// Reads Finder's Put Back records for the Trash, off the main thread.
    func refreshFinderPutBack() {
        let trash = paths.trash
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { FinderPutBack.originals(trash: trash) }.value
            self?.finderPutBack = found
        }
    }

    // MARK: Progress

    /// Shows progress at most every `progressInterval`; the end of an
    /// operation is shown at once, and a later step never follows it.
    private func progressArrived(_ step: OperationProgress) {
        let now = Date()
        if step.isFinished || now.timeIntervalSince(lastProgress) >= Self.progressInterval {
            pendingProgress = nil
            lastProgress = now
            transfers.apply(step)
            return
        }
        pendingProgress = step
        guard progressFlush == nil else { return }
        progressFlush = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.progressInterval * 1_000_000_000))
            guard let self else { return }
            self.progressFlush = nil
            if let pending = self.pendingProgress {
                self.pendingProgress = nil
                self.lastProgress = Date()
                self.transfers.apply(pending)
            }
        }
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

    /// A task's state for the log: "queued", "started", "finished (1 item)".
    nonisolated static func describe(_ state: FileTaskState) -> String {
        switch state {
        case .queued: return "queued"
        case .running: return "started"
        case .finished(let items): return "finished (\(items) item\(items == 1 ? "" : "s"))"
        case .failed(let why): return "failed (\(why))"
        case .cancelled: return "cancelled"
        }
    }

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
