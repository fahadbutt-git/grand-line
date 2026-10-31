import AppKit
import LauncherKit
import QueryKit

/// The action panel (Command+K): the selected row's actions, or a list of apps for Open With.
struct ActionPanelState: Equatable {
    var title: String
    var actions: [LaunchAction]
    var selected: Int
    var result: LaunchResult
}

/// Everything the search window shows, and what each key does.
@MainActor
final class SearchModel: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var list = ResultList()
    @Published private(set) var chips: [String] = []
    @Published private(set) var status = ""
    @Published var actionPanel: ActionPanelState?
    @Published private(set) var gate = ConfirmationGate()
    @Published var previewOpen = false

    let services: Services
    let performer: ActionPerformer
    weak var field: NSTextField?
    var hide: () -> Void = {}
    var show: () -> Void = {}
    /// The window is coming back to show a change that failed after it closed.
    private var reopeningForFailure = false
    private var task: Task<Void, Never>?
    private var query = LaunchQuery(raw: "")

    init(services: Services) {
        self.services = services
        self.performer = ActionPerformer(paths: services.paths)
    }

    // MARK: Searching

    /// Instant providers answer on the keystroke; slower ones merge in below.
    func setText(_ newText: String, fromField: Bool = true) {
        text = newText
        if !fromField { field?.stringValue = newText; moveCursorToEnd() }
        gate.cancel()
        actionPanel = nil
        let engine = services.engine
        let plan = engine.plan(newText)
        query = plan.query
        chips = plan.query.prefix == .files ? QueryChips.describe(QueryParser.parse(plan.query.term)) : []
        let started = Date()
        list.replace(with: engine.instantGroups(plan), limitScale: plan.limitScale, topHit: plan.topHit)
        status = statusText(milliseconds: Int(Date().timeIntervalSince(started) * 1000))
        readSettingsIfShown()
        task?.cancel()
        task = Task { [weak self] in
            for await update in engine.search(plan, includeInstant: false) {
                guard let self, !Task.isCancelled else { return }
                switch update {
                case .merge(let rows): self.list.merge(rows)
                case .replace(let groups, let scale): self.list.replace(with: groups, limitScale: scale, topHit: plan.topHit)
                case .finished(let ms): self.status = self.statusText(milliseconds: ms)
                }
            }
        }
    }

    func refresh() { setText(text, fromField: true) }

    private func statusText(milliseconds: Int) -> String {
        let count = list.rows.filter { !$0.isFallback }.count
        return count == 0 ? "" : "\(count) result\(count == 1 ? "" : "s") · \(milliseconds) ms"
    }

    private func moveCursorToEnd() {
        guard let editor = field?.currentEditor() else { return }
        editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    // MARK: Keys

    /// Returns false to let the key reach the text field.
    func handle(_ command: KeyCommand) -> Bool {
        if actionPanel != nil, handlePanel(command) { return true }
        if gate.isConfirming, command != .primary, command != .escape { gate.cancel() }
        switch command {
        case .moveUp: list.moveSelection(by: -1)
        case .moveDown: list.moveSelection(by: 1)
        case .pageUp: list.moveSelection(by: -8)
        case .pageDown: list.moveSelection(by: 8)
        case .primary: runSelected(index: 0)
        case .secondary: runSelected(index: 1)
        case .runRow(let n):
            guard let row = list.row(shortcut: n), let action = row.primary else { return true }
            run(action, on: row)
        case .actions: openActionPanel()
        case .escape: escape()
        case .complete: complete()
        case .togglePreview: previewOpen.toggle()
        case .copy:
            guard let row = list.selected else { return false }
            performer.copy(copyText(row))
        case .shortcut(let shortcut):
            guard let row = list.selected, let action = row.actions.first(where: { $0.shortcut == shortcut }) else { return false }
            run(action, on: row)
        }
        return true
    }

    private func handlePanel(_ command: KeyCommand) -> Bool {
        guard var panel = actionPanel else { return false }
        switch command {
        case .moveUp: panel.selected = max(0, panel.selected - 1)
        case .moveDown: panel.selected = min(panel.actions.count - 1, panel.selected + 1)
        case .primary:
            guard panel.actions.indices.contains(panel.selected) else { return true }
            let action = panel.actions[panel.selected]
            actionPanel = nil
            run(action, on: panel.result)
            return true
        case .actions:
            actionPanel = nil
            return true
        case .escape:
            escape()
            return true
        default:
            return false
        }
        actionPanel = panel
        return true
    }

    private func escape() {
        switch EscapeRule.outcome(actionPanelOpen: actionPanel != nil, confirming: gate.isConfirming, query: text) {
        case .closeActionPanel: actionPanel = nil
        case .cancelConfirmation: gate.cancel()
        case .clearQuery: setText("", fromField: false)
        case .closeWindow: hide()
        }
    }

    private func complete() {
        guard let row = list.selected else { return }
        if let action = row.actions.first(where: { if case .setQuery = $0.command { return true } else { return false } }),
           case .setQuery(let next) = action.command {
            setText(next, fromField: false)
        } else if query.prefix == nil, !query.isPath {
            setText(row.title, fromField: false)
        }
    }

    private func copyText(_ row: LaunchResult) -> String {
        for action in row.actions {
            if case .copyText(let text) = action.command { return text }
        }
        return row.previewPath ?? row.title
    }

    private func openActionPanel() {
        guard let row = list.selected, !row.actions.isEmpty else { return }
        actionPanel = ActionPanelState(title: row.title, actions: row.actions, selected: 0, result: row)
    }

    // MARK: Running

    func select(_ row: LaunchResult) {
        list.select(id: row.id)
    }

    private func runSelected(index: Int) {
        guard let row = list.selected, row.actions.indices.contains(index) else { return }
        run(row.actions[index], on: row)
    }

    func run(_ action: LaunchAction, on row: LaunchResult) {
        guard gate.shouldRun(action, on: row.id) else { return }
        if row.providerID == SettingsActionsProvider.providerID, runSetting(action, on: row) { return }
        switch action.command {
        case .toggleFavourite:
            services.usage.toggleFavourite(row)
            refresh()
            return
        case .quickLook:
            previewOpen.toggle()
            return
        case .setQuery(let next):
            setText(next, fromField: false)
            return
        case .openWith(let path):
            actionPanel = ActionPanelState(title: "Open with", actions: performer.openWithActions(path), selected: 0, result: row)
            return
        default:
            break
        }
        services.usage.record(row, query: query)
        if let path = row.previewPath { services.names.noteOpened(path) }
        if action.closesWindow { hide() }
        performer.perform(action.command)
    }

    // MARK: Settings

    /// Each opening reads the settings' state afresh, once a settings row is on screen.
    func panelDidOpen() {
        if reopeningForFailure {
            reopeningForFailure = false
            return
        }
        services.settingsActions.panelOpened()
    }

    private func readSettingsIfShown() {
        let settings = services.settingsActions
        guard list.rows.contains(where: { $0.providerID == SettingsActionsProvider.providerID }), settings.claimRead() else { return }
        Task { [weak self] in
            await settings.readState()
            self?.updateSettingRows()
        }
    }

    /// Redraws the settings rows in place, so nothing else on screen moves.
    private func updateSettingRows() {
        list.update(services.settingsActions.instantResults(for: query))
    }

    /// Runs a setting change off the main thread: the row says it is working,
    /// then shows the state read back, or why it failed. A second Return on
    /// the same row while it runs is ignored. Returns false for actions the
    /// window runs itself (opening a pane, a screenshot).
    private func runSetting(_ action: LaunchAction, on row: LaunchResult) -> Bool {
        let settings = services.settingsActions
        switch settings.begin(action, resultID: row.id) {
        case .notManaged:
            return false
        case .busy:
            return true
        case .started(let job):
            // Not recorded in Recents: the row's title is a state that will change.
            let closes = action.closesWindow || UserDefaults.standard.bool(forKey: SettingsActionsProvider.closeAfterChangeKey)
            if closes { hide() }
            updateSettingRows()
            Task { [weak self] in
                let failure = await settings.finish(job)
                guard let self else { return }
                if failure != nil, closes {
                    self.reopeningForFailure = true
                    self.show()
                }
                self.updateSettingRows()
            }
            return true
        }
    }

    // MARK: Layout

    /// The list's height: every row, up to about nine, with section headers.
    var listHeight: CGFloat {
        let rows = CGFloat(list.rows.count) * Metrics.row + CGFloat(list.groups.count) * Metrics.header
        return min(rows, Metrics.maxList)
    }
}

enum Metrics {
    static let width: CGFloat = 720
    static let preview: CGFloat = 340
    /// A result row: 30 at regular density (Settings, Appearance).
    static var row: CGFloat = 30
    static let header: CGFloat = 24
    static let maxList: CGFloat = 9 * 30 + 3 * 24
    /// The preview pane is as tall as the field, a full list and the footer.
    static let previewHeight: CGFloat = 44 + maxList + 30
    static let radius: CGFloat = 10
}
