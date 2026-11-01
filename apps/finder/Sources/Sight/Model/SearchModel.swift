import AppKit
import LauncherKit
import QueryKit

/// The action panel (Command+K): the selected row's actions, the buffer's,
/// or a list of apps for Open With. Its keys are LauncherKit's ActionPanelModel.
typealias ActionPanelState = ActionPanelModel

/// Everything the search window shows, and what each key does.
@MainActor
final class SearchModel: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var list = ResultList()
    @Published private(set) var chips: [String] = []
    /// The prefix or keyword in use, shown as a chip at the start of the field.
    @Published private(set) var scopeChip: String?
    /// Files collected with Command+B, shown as chips under the field.
    @Published private(set) var buffer = FileBuffer()
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
    /// Setting changes still running that keep the window open.
    private(set) var settingsRunningOpen = 0
    /// The window lost the keys while such a change ran.
    var keysLostDuringSetting = false
    private var task: Task<Void, Never>?
    private var query = LaunchQuery(raw: "")
    /// Keeps the top row still while the query grows.
    private var hold = TopRowHold()

    init(services: Services) {
        self.services = services
        self.performer = ActionPerformer(paths: services.paths)
        // The first searches after launch may be answered by the local copy
        // while the service connects; its fuller answer refines the list.
        services.names.onLateAnswer { [weak self] in
            Task { @MainActor in self?.refreshForLateFiles() }
        }
    }

    /// Searches again when files may be missing from what is shown, keeping the top row.
    private func refreshForLateFiles() {
        guard actionPanel == nil, !gate.isConfirming, !text.isEmpty, !query.isPath, query.prefix == nil || query.prefix == .files || query.prefix == .exact else { return }
        refresh()
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
        scopeChip = plan.chip
        chips = plan.query.prefix == .files ? QueryChips.describe(QueryParser.parse(plan.query.term)) : []
        let started = Date()
        list.replace(with: engine.instantGroups(plan, hold: &hold), limitScale: plan.limitScale, topHit: plan.topHit)
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
        if actionPanel != nil, command == .toggleBuffer { return true }
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
            // Selected, so a row that asks first is confirmed by Return on it.
            list.select(id: row.id)
            run(action, on: row)
        case .actions: openActionPanel()
        case .escape: escape()
        case .complete: complete()
        case .togglePreview: previewOpen.toggle()
        case .copy:
            guard let row = list.selected else { return false }
            performer.copy(copyText(row))
        case .toggleBuffer:
            guard let row = list.selected, buffer.toggle(row) else { NSSound.beep(); return true }
        case .shortcut(let shortcut):
            // Every action the panel would list, so Copy name (⇧⌘N) works without opening it.
            guard let row = list.selected, let action = ActionPanel.actions(for: row).first(where: { $0.shortcut == shortcut }) else { return false }
            run(action, on: row)
        }
        return true
    }

    private func handlePanel(_ command: KeyCommand) -> Bool {
        guard var panel = actionPanel else { return false }
        let outcome = panel.handle(command, gate: &gate)
        switch outcome {
        case .handled:
            actionPanel = panel
            return true
        case .close:
            actionPanel = nil
            return true
        case .run(let action):
            actionPanel = nil
            run(action, on: panel.result, confirmed: true, files: panel.files)
            return true
        case .passThrough:
            return false
        }
    }

    /// Clicking an action in the panel: as Return on it.
    func choosePanelAction(at index: Int) {
        guard var panel = actionPanel, panel.actions.indices.contains(index) else { return }
        panel.selected = index
        actionPanel = panel
        _ = handlePanel(.primary)
    }

    /// Takes one file out of the buffer (its chip's button).
    func removeFromBuffer(_ path: String) {
        buffer.remove(path)
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

    /// The buffer's actions while it holds files, else every action of the selected row.
    private func openActionPanel() {
        gate.cancel()
        if !buffer.isEmpty {
            let holder = LaunchResult(id: "buffer", title: buffer.title, icon: .symbol("tray.full"), section: .files, actions: [])
            actionPanel = ActionPanelState(title: buffer.title, actions: buffer.actions, result: holder, files: buffer.paths)
            return
        }
        guard let row = list.selected else { return }
        let actions = ActionPanel.actions(for: row)
        guard !actions.isEmpty else { return }
        actionPanel = ActionPanelState(title: row.title, actions: actions, result: row)
    }

    // MARK: Running

    func select(_ row: LaunchResult) {
        list.select(id: row.id)
    }

    private func runSelected(index: Int) {
        guard let row = list.selected, row.actions.indices.contains(index) else { return }
        run(row.actions[index], on: row)
    }

    /// - Parameters:
    ///   - confirmed: the action panel already asked its question.
    ///   - files: the buffer's files when the action came from the buffer's panel.
    func run(_ action: LaunchAction, on row: LaunchResult, confirmed: Bool = false, files: [String] = []) {
        guard confirmed || gate.shouldRun(action, on: row.id) else { return }
        if row.providerID == SettingsActionsProvider.providerID, runSetting(action, on: row) { return }
        switch action.command {
        case .buffer(let paths):
            buffer.toggle(paths: paths)
            return
        case .clearBuffer:
            buffer.clear()
            return
        case .script(let path, let value):
            choose(script: path, value: value)
            return
        case .files(.quickLook, let paths) where paths.count == 1 && row.previewPath == paths[0]:
            previewOpen.toggle()
            return
        case .toggleFavourite:
            // Clipboard entries and pids are never kept (UsagePolicy).
            guard UsagePolicy.mayFavourite(row) || services.usage.isFavourite(row.id) else { NSSound.beep(); return }
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
            actionPanel = ActionPanelState(title: "Open with", actions: performer.openWithActions(path), result: row)
            return
        case .quit(let pid, let force):
            // Only while the pid still runs the app the row named.
            if action.closesWindow { hide() }
            performer.quit(pid, force: force, expectedName: ProcessProvider.expectedName(of: row))
            return
        default:
            break
        }
        // UsagePolicy keeps out the buffer, the selection, clipboard entries
        // (what was copied never reaches usage.json), pids and anything that
        // restarts or quits.
        if UsagePolicy.mayRecord(row) {
            services.usage.record(row, query: query)
        }
        if let path = row.previewPath { services.names.noteOpened(path) }
        // Alfred empties the buffer once something was done with it.
        if !files.isEmpty, action.closesWindow, files == buffer.paths { buffer.clear() }
        if action.closesWindow { hide() }
        performer.perform(action.command)
    }

    // MARK: Script commands

    /// Runs the script again with the chosen value: its new rows replace the
    /// list (the query goes back to "name "), or it asks to close the window.
    private func choose(script path: String, value: String) {
        guard let provider = services.scripts.provider(path: path) else { return NSSound.beep() }
        status = "Running \(provider.script.name)…"
        Task { [weak self] in
            let reply = await provider.choose(value)
            guard let self else { return }
            switch reply {
            case .close:
                self.hide()
                self.setText("", fromField: false)
            case .rows:
                self.setText(provider.script.name + " ", fromField: false)
            case .failed(let why):
                self.status = why
            }
        }
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
            if closes { hide() } else { settingsRunningOpen += 1 }
            updateSettingRows()
            Task { [weak self] in
                let failure = await settings.finish(job)
                guard let self else { return }
                if failure != nil, closes {
                    self.reopeningForFailure = true
                    self.show()
                } else if !closes {
                    self.settingsRunningOpen -= 1
                    // A change that restarts Finder or the Dock (hidden files,
                    // desktop icons, Dock hiding) brings that app to the front;
                    // the window comes back, as it was, so the change can be seen.
                    // A click into any other app is left alone.
                    let restarted: Set<String> = ["com.apple.finder", "com.apple.dock"]
                    if self.settingsRunningOpen == 0, self.keysLostDuringSetting {
                        self.keysLostDuringSetting = false
                        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, restarted.contains(front) {
                            self.reopeningForFailure = true
                            self.show()
                        }
                    }
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
