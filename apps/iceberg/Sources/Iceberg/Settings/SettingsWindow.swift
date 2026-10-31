import AppKit
import Combine
import EventKit
import SwiftUI
import IcebergKit

/// The Settings window: what the panel shows and in what order, and the
/// general options. Every change is written to iceberg.toml at once (the
/// rest of the file, comments included, is kept) and the panel follows.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let host: PanelHost
    private let permissions: PermissionStatus
    private let recorder: ShortcutRecorder
    private var window: NSWindow?
    private var themeSink: AnyCancellable?

    init(host: PanelHost) {
        self.host = host
        self.permissions = PermissionStatus()
        self.recorder = ShortcutRecorder()
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        permissions.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let root = SettingsView(host: host, user: host.user, theme: host.theme, permissions: permissions, recorder: recorder)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Iceberg Settings"
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 480, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("IcebergSettings")
        applyAppearance(host.theme.theme, to: window)
        // Published before the value changes, so the new theme comes in the call.
        themeSink = host.theme.$theme.sink { [weak self, weak window] theme in
            guard let window else { return }
            self?.applyAppearance(theme, to: window)
        }
        return window
    }

    private func applyAppearance(_ theme: Theme, to window: NSWindow) {
        window.appearance = NSAppearance(named: theme.mode == .light ? .aqua : .darkAqua)
        window.backgroundColor = NSColor(srgbRed: theme.background.red, green: theme.background.green,
                                         blue: theme.background.blue, alpha: 1)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        permissions.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.cancel()
    }
}

/// Records a new keyboard shortcut in Settings: the next key pressed with
/// Control, Option or Command becomes the shortcut; Escape cancels. The
/// current shortcut is let go meanwhile, so pressing it records it rather
/// than toggling the panel.
@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var hint: String?
    private var monitor: Any?
    private var done: (@MainActor (KeyShortcut?) -> Void)?

    func start(_ onDone: @escaping @MainActor (KeyShortcut?) -> Void) {
        cancel()
        done = onDone
        recording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { () -> NSEvent? in
                guard let self else { return event }
                return self.handle(event)
            }
        }
    }

    func cancel() {
        guard recording else { return }
        finish(nil)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 && event.modifierFlags.intersection([.control, .option, .command]).isEmpty {
            finish(nil)
            return nil
        }
        var modifiers: KeyShortcut.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        guard let shortcut = KeyShortcut(keyCode: event.keyCode, modifiers: modifiers) else {
            hint = "Hold Control, Option or Command with the key (Escape cancels)."
            return nil
        }
        finish(shortcut)
        return nil
    }

    private func finish(_ shortcut: KeyShortcut?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        hint = nil
        let done = self.done
        self.done = nil
        done?(shortcut)
    }
}

/// Calendars and Reminders access as macOS has it now. Read again each
/// time the window comes forward, since it changes in System Settings.
@MainActor
final class PermissionStatus: ObservableObject {
    enum State: Equatable { case allowed, denied, notAsked }
    @Published private(set) var states: [PanelPermission: State] = [:]

    func refresh() {
        var next: [PanelPermission: State] = [:]
        for permission in [PanelPermission.calendars, .reminders] {
            let type: EKEntityType = permission == .calendars ? .event : .reminder
            switch EKEventStore.authorizationStatus(for: type) {
            case .fullAccess: next[permission] = .allowed
            case .notDetermined: next[permission] = .notAsked
            default: next[permission] = .denied
            }
        }
        if next != states { states = next }
    }

    func openPrivacySettings(_ permission: PanelPermission) {
        let anchor = permission == .calendars ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// One row of the list: a built-in item or a script widget.
struct PanelRow: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var permission: PanelPermission?
    /// The widget's file says `enabled = false`, so it cannot be turned on here.
    var lockedOff = false
}

struct SettingsView: View {
    @ObservedObject var host: PanelHost
    @ObservedObject var user: UserWidgets
    @ObservedObject var theme: ThemeStore
    @ObservedObject var permissions: PermissionStatus
    @ObservedObject var recorder: ShortcutRecorder
    @Local private var failure: String?

    var body: some View {
        let rows = allRows
        let shown = host.layout.enabled.compactMap { id in rows.first { $0.id == id } }
        let hidden = rows.filter { !host.layout.isEnabled($0.id) }
        VStack(alignment: .leading, spacing: 0) {
            if let failure {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(failure).lineLimit(3)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.color(.theme(.red)) ?? theme.foreground)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            List {
                Section {
                    ForEach(shown) { row in
                        SettingsRowView(row: row, on: true, permissions: permissions,
                                        canMoveUp: row.id != shown.first?.id, canMoveDown: row.id != shown.last?.id,
                                        toggle: { set(row.id, $0) },
                                        move: { move(row.id, by: $0, among: shown.map(\.id)) })
                    }
                    .onMove { offsets, destination in
                        let ids = offsets.map { shown[$0].id }
                        var layout = host.layout
                        layout.move(ids, before: destination < shown.count ? shown[destination].id : nil)
                        failure = host.save(layout)
                    }
                    if shown.isEmpty {
                        Text("Nothing is shown. Turn something on below.")
                            .font(.system(size: 13)).foregroundStyle(theme.muted)
                    }
                } header: {
                    SettingsHeader(text: "Shown in the panel", note: "Drag, or use the arrows, to change the order.")
                }

                if !hidden.isEmpty {
                    Section {
                        ForEach(hidden) { row in
                            SettingsRowView(row: row, on: false, permissions: permissions,
                                            canMoveUp: false, canMoveDown: false,
                                            toggle: { set(row.id, $0) }, move: { _ in })
                        }
                    } header: {
                        SettingsHeader(text: "Not shown")
                    }
                }

                Section {
                    HStack(spacing: 8) {
                        Button("Show widgets folder") { user.openFolder() }
                        Button("Open iceberg.toml") { openSettingsFile() }
                        Button("Open the log") { NSWorkspace.shared.open(Log.file) }
                    }
                    .controlSize(.small)
                    Text("A widget is a small file in the widgets folder: a title, an SF Symbol and a shell command. New ones appear here, turned off.")
                        .font(.system(size: 11)).foregroundStyle(theme.muted)
                } header: {
                    SettingsHeader(text: "Widgets")
                }

                Section {
                    general
                } header: {
                    SettingsHeader(text: "General")
                }

                if let player = host.nowPlaying {
                    Section {
                        NowPlayingHealthRow(model: player)
                    } header: {
                        SettingsHeader(text: "Now Playing", note: "Where what is playing comes from.")
                    }
                }

                Section {
                    DiagnosticsView(user: user, settings: host.settings)
                } header: {
                    SettingsHeader(text: "Diagnostics", note: "What each widget in the panel has done since Iceberg started.")
                }

                let issues = host.allIssues
                if !issues.isEmpty {
                    Section {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            ProblemRow(issue: issue)
                        }
                    } header: {
                        SettingsHeader(text: "Problems", note: "Files Iceberg could not fully read. The rest keeps working, and a saved fix applies at once.")
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(theme.background)
        .tint(theme.highlight)
        .environmentObject(theme)
        .preferredColorScheme(theme.colorScheme)
        .frame(minWidth: 480, minHeight: 420)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Open the panel", selection: Binding(
                get: { host.settings.openOn },
                set: { failure = host.save("open_on", .string($0.rawValue)) })) {
                Text("When the pointer rests on the notch").tag(IcebergSettings.OpenOn.hover)
                Text("When the notch is clicked").tag(IcebergSettings.OpenOn.click)
            }
            Stepper(value: Binding(
                get: { host.settings.hoverDelay },
                set: { failure = host.save("hover_delay", .float((min(max($0, 0), 3) * 100).rounded() / 100)) }),
                    in: 0...3, step: 0.05) {
                Text("Hover delay: \(Self.seconds(host.settings.hoverDelay))")
            }
            .disabled(host.settings.openOn != .hover)
            .help("How long the pointer rests on the notch before the panel opens. Longer stops it opening as you pass to the menu bar.")
            shortcutRow
            Picker("Show on", selection: Binding(
                get: { host.settings.externalDisplays },
                set: { failure = host.save("external_displays", .string($0.rawValue)) })) {
                Text("The built-in display").tag(IcebergSettings.ExternalDisplays.none)
                Text("Every display (a pill where there is no notch)").tag(IcebergSettings.ExternalDisplays.pill)
            }
            settingToggle("Artwork and playing bars beside the closed notch", key: "live_activity", value: host.settings.liveActivity)
            settingToggle("Iceberg in the menu bar", key: "menu_bar_icon", value: host.settings.menuBarIcon)
            settingToggle("Open at login", key: "launch_at_login", value: host.settings.launchAtLogin)
        }
        .font(.system(size: 13))
    }

    private var shortcutRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Open or close with")
                Button(action: recordShortcut) {
                    Text(recorder.recording ? "Type a shortcut…" : (host.settings.toggleShortcut?.symbols ?? "None"))
                        .font(.system(size: 12, weight: .medium).monospaced())
                        .frame(minWidth: 90)
                }
                .help("Click, then press the keys. Escape cancels.")
                if host.settings.toggleShortcut != KeyShortcut.defaultToggle {
                    Button("Reset") { failure = host.save("toggle_shortcut", .string(KeyShortcut.defaultToggle.text)) }
                        .controlSize(.small)
                }
                if host.settings.toggleShortcut != nil {
                    Button("Turn off") { failure = host.save("toggle_shortcut", .string("")) }
                        .controlSize(.small)
                }
            }
            if let hint = recorder.hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(theme.muted)
            } else if let problem = host.hotKeyProblem {
                Text(problem).font(.system(size: 11)).foregroundStyle(theme.color(.theme(.red)) ?? theme.foreground)
            }
        }
    }

    private func recordShortcut() {
        if recorder.recording {
            recorder.cancel()
            return
        }
        host.suspendShortcut()
        recorder.start { shortcut in
            if let shortcut { failure = host.save("toggle_shortcut", .string(shortcut.text)) }
            host.resumeShortcut()
        }
    }

    static func seconds(_ s: TimeInterval) -> String {
        String(format: "%.2f s", s)
    }

    private func settingToggle(_ title: String, key: String, value: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { failure = host.save(key, .bool($0)) }))
            .toggleStyle(.checkbox)
    }

    private var allRows: [PanelRow] {
        var rows = PanelCatalog.builtins.map {
            PanelRow(id: $0.id, title: $0.title, detail: $0.detail, symbol: $0.symbol, permission: $0.permission)
        }
        for w in user.available where !PanelCatalog.isBuiltin(w.id) {
            rows.append(PanelRow(id: w.id, title: w.title, detail: Self.detail(for: w), symbol: Self.symbol(w.icon)))
        }
        for w in user.disabledInFile where !PanelCatalog.isBuiltin(w.id) {
            rows.append(PanelRow(id: w.id, title: w.title, detail: "Turned off in its file (enabled = false).",
                                 symbol: Self.symbol(w.icon), lockedOff: true))
        }
        return rows
    }

    static func detail(for w: WidgetConfig) -> String {
        let file = w.file?.lastPathComponent ?? "\(w.id).toml"
        var text = "Widget from \(file), \(w.mode.description)"
        if w.runsWhileClosed { text += ", also while the panel is closed" }
        if w.always { text += ", even in Low Power Mode" }
        return text + "."
    }

    static func symbol(_ name: String) -> String {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : WidgetConfig.defaultIcon
    }

    private func set(_ id: String, _ on: Bool) {
        var layout = host.layout
        layout.set(id, enabled: on)
        failure = host.save(layout)
    }

    private func move(_ id: String, by offset: Int, among visible: [String]) {
        var layout = host.layout
        layout.move(id, by: offset, among: visible)
        failure = host.save(layout)
    }

    private func openSettingsFile() {
        let url = host.paths.settingsFile
        if !FileManager.default.fileExists(atPath: url.path) {
            failure = host.save("open_on", .string(host.settings.openOn.rawValue))
        }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsHeader: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground)
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(theme.muted) }
        }
        .padding(.top, 6)
    }
}

private struct SettingsRowView: View {
    @EnvironmentObject var theme: ThemeStore
    let row: PanelRow
    let on: Bool
    @ObservedObject var permissions: PermissionStatus
    let canMoveUp: Bool
    let canMoveDown: Bool
    let toggle: (Bool) -> Void
    let move: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbol)
                .font(.system(size: 13))
                .foregroundStyle(on ? theme.highlight : theme.muted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 13)).foregroundStyle(theme.foreground)
                Text(row.detail).font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                if let permission = row.permission, let note = note(permission) {
                    HStack(spacing: 6) {
                        Text(note).font(.system(size: 11)).foregroundStyle(theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if permissions.states[permission] == .denied {
                            Button("Open Privacy Settings") { permissions.openPrivacySettings(permission) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            if on {
                HStack(spacing: 2) {
                    arrow("chevron.up", enabled: canMoveUp, help: "Move up") { move(-1) }
                    arrow("chevron.down", enabled: canMoveDown, help: "Move down") { move(1) }
                }
            }
            Toggle("", isOn: Binding(get: { on }, set: { toggle($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(row.lockedOff)
        }
        .padding(.vertical, 3)
    }

    private func note(_ permission: PanelPermission) -> String? {
        switch permissions.states[permission] {
        case .denied?:
            return "Hidden: Iceberg may not read \(permission.name). Allow it in System Settings, Privacy & Security, \(permission.name)."
        case .notAsked?:
            return "macOS asks for \(permission.name) access the first time the panel opens."
        default:
            return nil
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }
}
