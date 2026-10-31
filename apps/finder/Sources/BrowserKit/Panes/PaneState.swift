import ArchiveKit
import Foundation

/// What opening the selection does (Return, Cmd+O, Cmd+Down, double-click).
public struct OpenAction: Equatable, Sendable {
    /// Go here in this pane: a folder, or into an archive or a folder in one.
    public var navigate: BrowserLocation?
    /// Open in their apps.
    public var launch: [URL] = []
    /// Several folders open in windows of their own, as in Finder.
    public var windows: [URL] = []
    /// Files inside an archive: extracted to a temporary folder, then opened.
    public var fromArchive: [FileItem] = []

    public var isEmpty: Bool { navigate == nil && launch.isEmpty && windows.isEmpty && fromArchive.isEmpty }
}

/// One pane, without any UI: where it is, its rows in order, the selection and
/// how it is sorted and shown.
public struct PaneState: Equatable, Sendable {
    public private(set) var history: NavigationHistory
    public private(set) var loaded: [FileItem] = []
    public private(set) var items: [FileItem] = []
    public private(set) var ids: [String] = []
    public var selection = SelectionModel()
    public private(set) var settings: ViewSettings
    public private(set) var folderSizes: [String: Int64] = [:]
    /// Last-opened dates by path, read only while sorting by them.
    public private(set) var lastOpened: [String: Date] = [:]
    public private(set) var manualOrder: [String] = []

    public init(location: BrowserLocation, settings: ViewSettings = ViewSettings()) {
        self.history = NavigationHistory(location)
        self.settings = settings
    }

    public var location: BrowserLocation { history.current }

    public var selectedItems: [FileItem] {
        items.filter { selection.contains($0.id) }
    }

    public func item(id: String) -> FileItem? {
        items.first { $0.id == id }
    }

    // MARK: Contents

    /// New contents for the current place; the selection keeps what is still there.
    public mutating func load(_ newItems: [FileItem]) {
        loaded = newItems
        resort()
        selection.prune(to: ids)
    }

    public mutating func setSettings(_ new: ViewSettings) {
        let resorting = new.sort != settings.sort
        settings = new
        if resorting { resort() }
    }

    public mutating func setSize(_ bytes: Int64, for path: String) {
        guard folderSizes[path] != bytes else { return }
        folderSizes[path] = bytes
        if settings.sort.field == .size { resort() }
    }

    public mutating func setLastOpened(_ dates: [String: Date]) {
        lastOpened.merge(dates) { _, new in new }
        if settings.sort.field == .lastOpened { resort() }
    }

    public mutating func setManualOrder(_ names: [String]) {
        manualOrder = names
        if settings.sort.field == .manual { resort() }
    }

    /// Dragging rows to a new place switches to manual order (R7). Returns the
    /// order to store for the folder.
    @discardableResult
    public mutating func moveManually(_ moving: [String], to index: Int) -> [String] {
        let order = ManualOrder.move(moving, to: index, in: items.map(\.name))
        manualOrder = order
        var changed = settings
        changed.sort = ItemSort(field: .manual, foldersFirst: false)
        settings = changed
        resort()
        return order
    }

    mutating func resort() {
        items = ItemSorter.sorted(loaded, by: settings.sort, folderSizes: folderSizes, lastOpened: lastOpened, manual: manualOrder)
        ids = items.map(\.id)
    }

    // MARK: Navigation

    /// Goes somewhere new. The caller then loads its contents.
    public mutating func navigate(to location: BrowserLocation, select: [URL] = []) {
        history.visit(location)
        loaded = []
        items = []
        ids = []
        selection.clear()
        manualOrder = []
        pendingSelection = select.map { $0.standardizedFileURL.path }
    }

    /// Paths to select once the new place has loaded (after Up, or a reveal).
    public private(set) var pendingSelection: [String] = []

    public mutating func applyPendingSelection() {
        guard !pendingSelection.isEmpty else { return }
        let wanted = Set(pendingSelection)
        let matching = items.filter { wanted.contains($0.url.standardizedFileURL.path) }.map(\.id)
        selection.set(matching, in: ids)
        pendingSelection = []
    }

    public mutating func goBack() -> Bool {
        guard history.back() != nil else { return false }
        resetContents()
        return true
    }

    public mutating func goForward() -> Bool {
        guard history.forward() != nil else { return false }
        resetContents()
        return true
    }

    /// Cmd+Up (R4): the enclosing folder, with the folder you came from selected.
    @discardableResult
    public mutating func goUp() -> Bool {
        guard let parent = location.parent else { return false }
        navigate(to: parent.location, select: parent.select.map { [$0] } ?? [])
        return true
    }

    /// Swaps the current place without a history entry, as a search is refined.
    public mutating func replace(with location: BrowserLocation) {
        history.replaceCurrent(location)
        resetContents()
    }

    mutating func resetContents() {
        loaded = []
        items = []
        ids = []
        selection.clear()
        pendingSelection = []
    }

    // MARK: Opening

    public func openAction(for chosen: [FileItem]) -> OpenAction {
        var action = OpenAction()
        let folders = chosen.filter(\.isFolder)
        for item in chosen where !item.isFolder {
            if item.isInArchive {
                action.fromArchive.append(item)
            } else if chosen.count == 1, Archive.isArchive(item.url) {
                action.navigate = .archive(item.url, entry: "")
            } else {
                action.launch.append(item.url)
            }
        }
        if folders.count == 1, action.navigate == nil {
            action.navigate = Self.location(of: folders[0], in: location)
        } else if folders.count > 1 {
            action.windows = folders.filter { !$0.isInArchive }.map(\.url)
        }
        return action
    }

    static func location(of folder: FileItem, in current: BrowserLocation) -> BrowserLocation {
        if let entry = folder.archiveEntry, case .archive(let archive, _) = current {
            return .archive(archive, entry: entry)
        }
        return .folder(folder.url)
    }
}
