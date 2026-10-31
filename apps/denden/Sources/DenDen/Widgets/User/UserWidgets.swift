import AppKit
import SwiftUI
import DenDenKit

/// The widgets you write without code: each file in
/// `~/.config/grand-line/denden/widgets/` names a shell command, and its
/// output is shown as a small chip. See README.md, "Adding a widget".
///
/// Commands run only while the panel is open (or when it opens), a few at a
/// time, each with a hard time limit. One timer is armed for the next due
/// widget and none at all while the panel is closed.
@MainActor
final class UserWidgets: ObservableObject {
    @Published private(set) var widgets: [WidgetConfig] = []
    @Published private(set) var displays: [String: WidgetDisplay] = [:]
    @Published private(set) var running: Set<String> = []
    @Published private(set) var issues: [ConfigIssue] = []

    private let paths: DenDenPaths
    private let theme: ThemeStore
    private let scheduler = RefreshScheduler()
    private let pool = CommandPool(maxConcurrent: 4)
    private var watcher: FileWatcher?
    private var timer: Timer?

    init(paths: DenDenPaths, theme: ThemeStore) {
        self.paths = paths
        self.theme = theme
        installExamplesIfFirstRun()
        reload()
        watcher = FileWatcher(paths: [paths.widgetsFolder]) { [weak self] in self?.reload() }
    }

    /// Reads every widget file again (also called when the folder changes).
    func reload() {
        let result = WidgetLoader.load(from: paths.widgetsFolder)
        Log.issues(result.issues, context: "widgets")
        let changed = Set(result.widgets.filter { new in !widgets.contains(new) }.map(\.id))
        widgets = result.widgets
        issues = result.issues
        scheduler.setWidgets(result.widgets.map { (id: $0.id, policy: $0.refresh) })
        for id in changed { scheduler.invalidate(id) }
        let ids = Set(result.widgets.map(\.id))
        displays = displays.filter { ids.contains($0.key) }
        if scheduler.isOpen { runDue(scheduler.due(at: Date()) + changed.filter { !runsOnInterval($0) }) }
    }

    func panelWillOpen() {
        start(scheduler.panelOpened(at: Date()))
        armTimer()
    }

    func panelDidClose() {
        scheduler.panelClosed()
        timer?.invalidate()
        timer = nil
    }

    /// Runs the click command, then the widget's own command to show the result.
    func click(_ widget: WidgetConfig) {
        guard let click = widget.click else {
            start([widget.id])
            return
        }
        pool.submit(id: "click:" + widget.id, command: click, timeout: 30,
                    workingDirectory: widget.file?.deletingLastPathComponent(),
                    environment: environment(for: widget)) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.start([widget.id]) }
        }
    }

    private func runsOnInterval(_ id: String) -> Bool {
        if case .interval = widgets.first(where: { $0.id == id })?.refresh { return true }
        return false
    }

    private func runDue(_ ids: [String]) {
        start(ids)
        armTimer()
    }

    private func start(_ ids: [String]) {
        for id in ids {
            guard let w = widgets.first(where: { $0.id == id }) else { continue }
            let accepted = pool.submit(id: w.id, command: w.command, timeout: w.timeout,
                                       workingDirectory: w.file?.deletingLastPathComponent(),
                                       environment: environment(for: w)) { [weak self] id, result in
                let shown = CommandOutputParser.display(for: result)
                Task { @MainActor [weak self] in self?.finished(id, shown) }
            }
            if accepted { running.insert(w.id) }
        }
    }

    private func finished(_ id: String, _ shown: WidgetDisplay) {
        running.remove(id)
        if displays[id] != shown { displays[id] = shown }
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
        // Let macOS fold this wake-up in with others.
        t.tolerance = min(5, max(0.5, delay * 0.1))
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func environment(for w: WidgetConfig) -> [String: String] {
        [
            "GRAND_LINE_DENDEN_WIDGET": w.id,
            "GRAND_LINE_DENDEN_WIDGETS_DIR": paths.widgetsFolder.path,
            "GRAND_LINE_DENDEN_THEME": theme.theme.name,
            "GRAND_LINE_DENDEN_MODE": theme.theme.mode.rawValue,
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
                Text(display?.text ?? (busy ? "…" : ""))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(display?.failed == true ? theme.muted : (tint ?? theme.foreground))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .frame(height: NotchMetrics.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? theme.selection : theme.raised)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    var helpText: String {
        var parts = [widget.title]
        if let d = display { parts.append(d.text) }
        if widget.click != nil { parts.append("Click to run its action") }
        return parts.joined(separator: "\n")
    }

    /// The symbol if macOS has it, so a typo shows a quiet square, not nothing.
    static func symbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : WidgetConfig.defaultIcon
    }
}
