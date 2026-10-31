import AppKit
import BrowserKit
import FileKit

/// One window: its panes (R12, R27), the view chosen for it (R28), and which
/// side panels show. Commands are in the Actions folder.
@MainActor
final class BrowserModel: ObservableObject {
    let services: Services
    @Published var layout: PaneLayout
    @Published private(set) var panes: [PaneModel] = []
    @Published var mode: ViewMode
    @Published var showSidebar = true
    @Published var showInspector = false
    @Published var showPreview = false
    @Published var showStatusBar = true
    @Published var showToolbar = true
    @Published var showPathBar = true
    @Published var showViewOptions = false
    @Published var showHidden = false
    @Published var sidebarWidth: Double = SidebarMetrics.defaultWidth
    @Published var editingPath = false
    @Published var pathText = ""
    /// Under the Go to Folder field: why Return went nowhere.
    @Published var pathProblem: String?
    @Published var searchText = ""
    @Published var searchFocused = false
    @Published var pinned = false
    @Published var showTransfers = false
    /// Increments to ask the focused list to start renaming its selection.
    @Published var renameRequest = 0
    weak var window: NSWindow?

    init(services: Services, location: BrowserLocation, select: [URL] = []) {
        self.services = services
        self.layout = PaneLayout()
        self.mode = services.viewPreferences.defaults.mode == .panes ? .list : services.viewPreferences.defaults.mode
        // Settings, General and Advanced.
        let prefs = NexusPreferencesStore.shared.current
        showPathBar = prefs.showPathBar
        showStatusBar = prefs.showStatusBar
        showHidden = prefs.showHiddenFiles
        let pane = makePane(location)
        panes = [pane]
        pane.go(location, select: select)
    }

    convenience init(services: Services, workspace: Workspace) {
        let restored = workspace.restorable(home: services.paths.home)
        self.init(services: services, location: restored.panes[0].location)
        for pane in restored.panes.dropFirst() {
            let model = makePane(pane.location)
            panes.append(model)
            model.go(pane.location)
        }
        layout = restored.layout
        mode = restored.layout.count > 1 ? .panes : restored.panes[0].mode
        pinned = restored.pinned
        sidebarWidth = restored.sidebarWidth
    }

    var focused: PaneModel { panes[min(layout.focused, panes.count - 1)] }

    /// The panes on screen: all of them in the panes view, else the focused one.
    var visiblePanes: [PaneModel] {
        mode == .panes ? Array(panes.prefix(layout.count)) : [focused]
    }

    func makePane(_ location: BrowserLocation) -> PaneModel {
        var settings = services.viewPreferences.defaults
        settings.mode = .list
        let pane = PaneModel(location: location, settings: settings, services: services)
        pane.showHidden = showHidden
        pane.onSelectionChange = { [weak self] in self?.selectionChanged() }
        return pane
    }

    func focus(_ pane: PaneModel) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        layout.focus(index)
        selectionChanged()
    }

    /// Sets how many panes there are, opening new ones at the focused folder.
    func setPaneCount(_ count: Int) {
        layout.setCount(count)
        while panes.count < layout.count {
            let start = focused.location.diskFolder.map { BrowserLocation.folder($0) } ?? .folder(services.paths.home)
            let pane = makePane(start)
            panes.append(pane)
            pane.go(start)
        }
        if layout.count == 1, mode == .panes { mode = .list }
        if layout.count > 1 { mode = .panes }
    }

    /// The selection file (contract with setup) and the inspector follow the focus.
    func selectionChanged() {
        objectWillChange.send()
        QuickLook.shared.selectionChanged(focused)
        window?.title = windowTitle
        guard NSApp.isActive, window?.isKeyWindow == true || window?.isMainWindow == true else { return }
        services.selectionFile.write(focused.selectedItems)
    }

    var windowTitle: String { focused.location.title }

    func snapshot(named name: String) -> Workspace {
        Workspace(
            name: name, layout: layout,
            panes: panes.prefix(layout.count).map { Workspace.Pane(location: $0.location, mode: mode) },
            pinned: pinned, sidebarWidth: sidebarWidth
        )
    }

    func tearDown() {
        for pane in panes { pane.tearDown() }
    }
}
