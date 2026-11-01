import AppKit
import SwiftUI
import IcebergKit

/// The widgets you write without code: each file in
/// `~/.config/grand-line/iceberg/widgets/` names a shell command, and its
/// output is shown as a small chip. See README.md, "Adding a widget".
///
/// Three kinds, as in Waybar: interval widgets run on their `refresh`
/// schedule, signal widgets run when `iceberg trigger NAME` asks, and stream
/// widgets keep one script running that prints a line per update.
///
/// What it costs is kept small: commands run only while the panel is open
/// (or as it opens) unless a widget says `updates = "always"`; at most
/// `max_concurrent` run at once, each with a hard time limit; nothing runs
/// during sleep or in Low Power Mode unless a widget says `always = true`;
/// a widget that keeps failing waits longer each time. One timer is armed
/// for the next due widget, and none while nothing is due.
@MainActor
final class UserWidgets: ObservableObject {
    /// The widgets the panel shows: those turned on, in the panel's order.
    @Published private(set) var widgets: [WidgetConfig] = []
    /// Every widget file that loads, for the Settings window.
    @Published private(set) var available: [WidgetConfig] = []
    /// Files that say `enabled = false`.
    @Published private(set) var disabledInFile: [WidgetConfig] = []
    @Published private(set) var displays: [String: WidgetDisplay] = [:]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var issues: [ConfigIssue] = []
    /// Run counts, times and last output per widget, for Settings › Diagnostics.
    @Published private(set) var stats: [String: WidgetStats] = [:]
    /// Sleep and Low Power Mode.
    @Published private(set) var gate = ResourceGate()
    /// Widgets showing their last good version while their file has a mistake.
    @Published private(set) var keptFromBefore: Set<String> = []
    /// When the widget files were last read, for Settings.
    @Published private(set) var lastReload: Date?

    private let paths: IcebergPaths
    private let theme: ThemeStore
    private let scheduler = RefreshScheduler()
    private let pool = CommandPool(maxConcurrent: 4)
    private var maxConcurrent = 4
    /// Stream widgets left waiting for a slot by `max_concurrent`.
    private var waitingStreams: Set<String> = []
    private var streams: [String: StreamProcess] = [:]
    private var streamRestarts: [String: DispatchWorkItem] = [:]
    private var streamFailures: [String: Int] = [:]
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// The panel's names, in order (`PanelLayout.enabled`).
    private var selection: [String] = []

    init(paths: IcebergPaths, theme: ThemeStore) {
        self.paths = paths
        self.theme = theme
        installExamplesIfFirstRun()
        gate.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        scheduler.isPaused = gate.isPaused
        reload()
        observePower()
    }

    var isOpen: Bool { scheduler.isOpen }

    // MARK: Files

    /// Reads every widget file again (the menu's Reload, and any change in
    /// the folder). The panel keeps running: widgets whose file did not
    /// change keep their value, changed ones run again at once.
    func reload() {
        let result = WidgetLoader.load(from: paths.widgetsFolder)
        Log.issues(result.issues, context: "widgets")
        let previous = available
        let merged = WidgetReload.keepLastGood(previous: previous, loaded: result)
        available = merged.widgets
        disabledInFile = result.disabled
        keptFromBefore = Set(merged.kept)
        var all = result.issues
        for id in merged.kept {
            let file = result.failed[id] ?? "\(id).toml"
            all.append(ConfigIssue(file: file, message: "keeps showing its last good version until the mistake is fixed",
                                   severity: .warning, fix: "Fix the error listed for this file and save; it reloads by itself."))
        }
        issues = all
        lastReload = Date()
        applySelection(changed: WidgetReload.changed(from: previous, to: available))
    }

    /// Files under the widgets folder were saved (hot reload). `names` are
    /// their file names: widget files reload, and widgets whose command
    /// names a saved script run again.
    func filesChanged(_ names: [String]) {
        reload()
        let scripts = WidgetReload.affected(byChangedFiles: names, widgets: widgets)
        let now = Date()
        for id in scripts.sorted() {
            // A script that writes the file it reads would run itself in a loop.
            if running.contains(id) { continue }
            if let last = stats[id]?.lastRun, now.timeIntervalSince(last) < 5 { continue }
            refresh(id, user: false)
        }
    }

    /// Shows the widgets named in `names` (the panel's whole list), in its order.
    func show(_ names: [String]) {
        guard names != selection else { return }
        selection = names
        applySelection(changed: [])
    }

    /// `max_concurrent` from iceberg.toml.
    func setMaxConcurrent(_ n: Int) {
        let n = max(1, n)
        guard n != maxConcurrent else { return }
        maxConcurrent = n
        pool.maxConcurrent = n
        syncStreams()
    }

    private func applySelection(changed: Set<String>) {
        let ids = PanelLayout(enabled: selection).widgets(available: available.map(\.id))
        let shown = ids.compactMap { id in available.first { $0.id == id } }
        let shownIDs = Set(shown.map(\.id))
        let fresh = shownIDs.subtracting(widgets.map(\.id)).union(changed.intersection(shownIDs))
        if shown != widgets { widgets = shown }
        scheduler.setWidgets(shown.filter { !$0.stream }.map {
            RefreshScheduler.Spec(id: $0.id, policy: $0.refresh, whileClosed: $0.runsWhileClosed, ignoresPause: $0.always)
        })
        for id in fresh {
            scheduler.invalidate(id)
            scheduler.resetBackoff(id)
            streamFailures[id] = nil
        }
        // A stream whose file changed starts again with the new command.
        for id in Array(streams.keys) where !shownIDs.contains(id) || fresh.contains(id) { stopStream(id) }
        for id in Array(streamRestarts.keys) where !shownIDs.contains(id) || fresh.contains(id) {
            streamRestarts[id]?.cancel()
            streamRestarts[id] = nil
        }
        displays = displays.filter { shownIDs.contains($0.key) }
        let known = Set(available.map(\.id))
        stats = stats.filter { known.contains($0.key) }
        syncStreams()

        let now = Date()
        var run = scheduler.due(at: now)
        for w in shown where fresh.contains(w.id) && !w.stream && w.refresh == .onOpen && !run.contains(w.id) {
            guard scheduler.isOpen, !scheduler.isHeldBack(w.id, at: now) else { continue }
            scheduler.markRun(w.id, at: now)
            run.append(w.id)
        }
        runDue(run)
    }

    // MARK: Panel, signals and clicks

    func panelWillOpen() {
        start(scheduler.panelOpened(at: Date()))
        syncStreams()
        armTimer()
    }

    func panelDidClose() {
        scheduler.panelClosed()
        syncStreams()
        armTimer()
    }

    /// `iceberg trigger NAME`: runs the widget now if it may run (the panel
    /// is open, or it updates always), or as soon as it may. A stream widget
    /// starts its script again. Returns false when no shown widget has that name.
    @discardableResult
    func trigger(_ name: String) -> Bool {
        let id = WidgetConfig.id(forFileName: name)
        guard widgets.contains(where: { $0.id == id }) else {
            Log.info("iceberg trigger \(name): no widget of that name is in the panel")
            return false
        }
        refresh(id, user: false)
        return true
    }

    /// Diagnostics' Run now: runs it at once, whatever its backoff.
    func runNow(_ id: String) {
        refresh(id, user: true)
    }

    /// Runs the click command, then the widget's own command to show the result.
    func click(_ widget: WidgetConfig) {
        guard let click = widget.click else {
            refresh(widget.id, user: true)
            return
        }
        pool.submit(id: "click:" + widget.id, command: click, timeout: 30,
                    workingDirectory: widget.file?.deletingLastPathComponent(),
                    environment: environment(for: widget)) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.refresh(widget.id, user: true) }
            }
        }
    }

    /// Runs (or restarts) one widget. `user` means someone asked directly
    /// (a click, Run now), which skips the backoff and the pause.
    private func refresh(_ id: String, user: Bool) {
        guard let w = widgets.first(where: { $0.id == id }) else { return }
        let now = Date()
        if user { scheduler.resetBackoff(id); streamFailures[id] = nil }
        if w.stream {
            stopStream(id)
            streamRestarts[id]?.cancel()
            streamRestarts[id] = nil
            syncStreams()
            return
        }
        let mayRunNow = scheduler.isOpen || w.runsWhileClosed
        if user || (mayRunNow && !scheduler.isHeldBack(id, at: now)) {
            scheduler.markRun(id, at: now)
            start([id])
        } else {
            // Runs on the next open, or once the pause or backoff is over.
            scheduler.invalidate(id)
            if mayRunNow { stats[id, default: WidgetStats()].recordSkip() }
        }
    }

    // MARK: Running commands

    private func runDue(_ ids: [String]) {
        start(ids)
        armTimer()
    }

    private func start(_ ids: [String]) {
        for id in ids {
            guard let w = widgets.first(where: { $0.id == id }), !w.stream else { continue }
            let accepted = pool.submit(id: w.id, command: w.command, timeout: w.timeout,
                                       workingDirectory: w.file?.deletingLastPathComponent(),
                                       environment: environment(for: w)) { [weak self] id, result in
                let shown = CommandOutputParser.display(for: result)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finished(id, result, shown) }
                }
            }
            if accepted { running.insert(w.id) }
        }
    }

    private func finished(_ id: String, _ result: CommandResult, _ shown: WidgetDisplay) {
        let now = Date()
        running.remove(id)
        stats[id, default: WidgetStats()].record(result, display: shown, at: now)
        scheduler.record(id, success: !shown.failed, at: now)
        if result.timedOut { Log.info("widget \(id): stopped after \(Int(result.timeout)) s") }
        guard widgets.contains(where: { $0.id == id }) else { return }
        if displays[id] != shown { displays[id] = shown }
        // A failure can push the next run back.
        if shown.failed { armTimer() }
    }

    private func armTimer() {
        timer?.invalidate()
        timer = nil
        let now = Date()
        guard let next = scheduler.nextWakeup(after: now) else { return }
        let delay = max(0.5, next.timeIntervalSince(now))
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.runDue(self.scheduler.due(at: Date()))
            }
        }
        // Let macOS fold this wake-up in with others (a tenth of the delay).
        t.tolerance = WakePolicy.tolerance(forDelay: delay)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Streams

    /// The stream widgets that should run now.
    private func wantedStreams() -> [WidgetConfig] {
        widgets.filter {
            $0.stream && (scheduler.isOpen || $0.runsWhileClosed) && gate.allows(always: $0.always)
        }
    }

    /// Starts the streams that should run now and stops the rest.
    private func syncStreams() {
        let wanted = wantedStreams()
        let wantedIDs = Set(wanted.map(\.id))
        for id in Array(streams.keys) where !wantedIDs.contains(id) { stopStream(id) }
        for id in Array(streamRestarts.keys) where !wantedIDs.contains(id) {
            streamRestarts[id]?.cancel()
            streamRestarts[id] = nil
        }
        let plan = StreamSlots.plan(wanted: wanted.map(\.id), running: Set(streams.keys),
                                    restarting: Set(streamRestarts.keys), max: maxConcurrent)
        for id in plan.waiting {
            stats[id, default: WidgetStats()].recordSkip()
            displays[id] = WidgetDisplay(text: "Waiting: \(maxConcurrent) streams already run", icon: "pause.circle",
                                         color: .theme(.muted), failed: true)
        }
        waitingStreams = Set(plan.waiting)
        for id in plan.start {
            if let w = wanted.first(where: { $0.id == id }) { startStream(w) }
        }
    }

    /// A stream ended by itself: a widget waiting for a slot takes it now,
    /// not at the next open or close (the one that ended is not restarted
    /// here; a failed one has its own restart timer).
    private func startWaitingStreams() {
        guard !waitingStreams.isEmpty else { return }
        let wanted = wantedStreams()
        let plan = StreamSlots.plan(wanted: wanted.map(\.id), running: Set(streams.keys),
                                    restarting: Set(streamRestarts.keys), max: maxConcurrent, eligible: waitingStreams)
        for id in plan.start {
            waitingStreams.remove(id)
            if let w = wanted.first(where: { $0.id == id }) { startStream(w) }
        }
    }

    private func startStream(_ w: WidgetConfig) {
        var env = CommandRunner.defaultEnvironment()
        for (k, v) in environment(for: w) { env[k] = v }
        let process = StreamProcess(command: w.command, workingDirectory: w.file?.deletingLastPathComponent(), environment: env)
        let id = w.id
        streams[id] = process
        running.insert(id)
        stats[id, default: WidgetStats()].recordStreamStart(at: Date())
        process.start(onLine: { [weak self, weak process] line in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let process else { return }
                    self?.streamLine(id, line, from: process)
                }
            }
        }, onExit: { [weak self, weak process] exit in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.streamEnded(id, exit, from: process)
                }
            }
        })
    }

    private func streamLine(_ id: String, _ line: String, from process: StreamProcess) {
        guard streams[id] === process else { return }
        running.remove(id)
        stats[id, default: WidgetStats()].recordStreamLine(line, at: Date())
        let shown = CommandOutputParser.parse(line)
        if displays[id] != shown { displays[id] = shown }
    }

    private func streamEnded(_ id: String, _ exit: StreamExit, from process: StreamProcess?) {
        // A stream that was stopped or replaced has already been let go.
        guard let process, streams[id] === process else { return }
        streams[id] = nil
        running.remove(id)
        // Its slot goes to a widget waiting for one (after the restart, if
        // any, is set up below, so this one keeps its turn).
        defer { startWaitingStreams() }
        stats[id, default: WidgetStats()].recordStreamExit(exit, at: Date())
        guard exit.isFailure else { return }
        // A stream that ran a good while before ending starts over gently.
        let failures = exit.duration > 60 ? 1 : (streamFailures[id] ?? 0) + 1
        streamFailures[id] = failures
        Log.info("widget \(id): \(exit.reason); starting it again in \(Int(FailureBackoff.streamDelay(afterFailures: failures))) s")
        if exit.lines == 0 || exit.launchError != nil {
            displays[id] = WidgetDisplay(text: CommandOutputParser.clean(exit.reason), icon: "exclamationmark.triangle",
                                         color: .theme(.muted), failed: true)
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.streamRestarts[id] = nil
                self.syncStreams()
            }
        }
        streamRestarts[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FailureBackoff.streamDelay(afterFailures: failures), execute: work)
    }

    private func stopStream(_ id: String) {
        streams[id]?.stop()
        streams[id] = nil
        running.remove(id)
    }

    // MARK: Sleep and Low Power Mode

    private func observePower() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setGate(asleep: true) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setGate(asleep: false) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setGate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) }
        })
    }

    private func setGate(asleep: Bool? = nil, lowPower: Bool? = nil) {
        var next = gate
        if let asleep { next.asleep = asleep }
        if let lowPower { next.lowPower = lowPower }
        guard next != gate else { return }
        let wasPaused = gate.isPaused
        gate = next
        scheduler.isPaused = next.isPaused
        Log.info(next.reason.map { "Widgets paused: \($0)" } ?? "Widgets running again")
        if wasPaused && !next.isPaused {
            start(scheduler.resumed(at: Date()))
        }
        syncStreams()
        armTimer()
    }

    // MARK: Settings › Diagnostics

    /// A short line on what the widget is doing now, or nil when all is well.
    func status(of w: WidgetConfig) -> String? {
        let now = Date()
        if !gate.allows(always: w.always), let reason = gate.reason { return "Paused: \(reason.lowercasedFirstLetter)" }
        if keptFromBefore.contains(w.id) { return "Showing its last good version: its file has a mistake" }
        if let until = scheduler.backoffUntil(w.id, at: now) {
            return "Failing; next try at \(until.formatted(date: .omitted, time: .shortened))"
        }
        if w.stream {
            if streams[w.id] != nil { return "Running" }
            if streamRestarts[w.id] != nil { return "Ended; starting again shortly" }
            return w.runsWhileClosed || scheduler.isOpen ? nil : "Stopped while the panel is closed"
        }
        return nil
    }

    private func environment(for w: WidgetConfig) -> [String: String] {
        [
            "GRAND_LINE_ICEBERG_WIDGET": w.id,
            "GRAND_LINE_ICEBERG_WIDGETS_DIR": paths.widgetsFolder.path,
            "GRAND_LINE_ICEBERG_THEME": theme.theme.name,
            "GRAND_LINE_ICEBERG_MODE": theme.theme.mode.rawValue,
        ]
    }

    /// On the very first run, copies the example widgets shipped in the app
    /// into the widgets folder. Never touches a folder that already exists.
    private func installExamplesIfFirstRun() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: paths.widgetsFolder.path),
              let examples = Bundle.main.resourceURL?.appendingPathComponent("examples/widgets"),
              let names = try? fm.contentsOfDirectory(atPath: examples.path) else { return }
        do {
            try fm.createDirectory(at: paths.widgetsFolder, withIntermediateDirectories: true)
            for name in names {
                let target = paths.widgetsFolder.appendingPathComponent(name)
                try fm.copyItem(at: examples.appendingPathComponent(name), to: target)
                if name.hasSuffix(".sh") {
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                }
            }
        } catch {
            Log.info("Could not install the example widgets: \(error.localizedDescription)")
        }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: paths.widgetsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(paths.widgetsFolder)
    }
}

private extension String {
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// The chips, three to a row, scrolling past four rows.
struct UserWidgetGrid: View {
    @ObservedObject var model: UserWidgets
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: NotchMetrics.chipSpacing), count: NotchMetrics.chipColumns)
        let rows = NotchGeometry.chipRows(for: model.widgets.count)
        let grid = LazyVGrid(columns: columns, spacing: NotchMetrics.chipSpacing) {
            ForEach(model.widgets) { w in
                UserWidgetChip(widget: w, display: model.displays[w.id], busy: model.running.contains(w.id)) {
                    model.click(w)
                }
            }
        }
        if rows > NotchMetrics.maxVisibleChipRows {
            ScrollView(.vertical, showsIndicators: false) { grid }
        } else {
            grid
        }
    }
}

private struct UserWidgetChip: View {
    @EnvironmentObject var theme: ThemeStore
    let widget: WidgetConfig
    let display: WidgetDisplay?
    let busy: Bool
    let action: @MainActor () -> Void
    @Local private var hovering = false

    var body: some View {
        let tint = theme.color(display?.color)
        let shown = display.map { ChipText.shown($0.text) }
        let quiet = display?.failed == true || shown?.needsSetup == true
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: Self.symbol(display?.icon ?? widget.icon))
                    .font(.system(size: 11))
                    .foregroundStyle(tint ?? theme.muted)
                    .frame(width: 14)
                Text(widget.title)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .layoutPriority(0)
                Spacer(minLength: 4)
                Text(shown?.text ?? (busy ? "…" : ""))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(quiet ? theme.muted : (tint ?? theme.foreground))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .frame(height: NotchMetrics.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? theme.selection : theme.card)
            )
            .overlay(alignment: .bottom) {
                // Waybar's `percentage`: a thin bar along the chip's foot.
                if let p = display?.percentage {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint ?? theme.highlight)
                            .frame(width: max(2, (geo.size.width - 12) * p / 100), height: 2)
                            .offset(x: 6, y: geo.size.height - 3)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    var helpText: String {
        var parts = [widget.title]
        if let d = display {
            parts.append(d.text)
            if let tooltip = d.tooltip, tooltip != d.text { parts.append(tooltip) }
            if ChipText.shown(d.text).needsSetup { parts.append("See the widget's file for what it needs") }
        }
        if widget.click != nil { parts.append("Click to run its action") }
        return parts.joined(separator: "\n")
    }

    /// The symbol if macOS has it, so a typo shows a quiet square, not nothing.
    static func symbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : WidgetConfig.defaultIcon
    }
}
