import AppKit
import Combine
import EventKit
import SwiftUI
import DenDenKit

/// The Settings window: what the panel shows and in what order, and the
/// general options. Every change is written to denden.toml at once (the
/// rest of the file, comments included, is kept) and the panel follows.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let host: PanelHost
    private let permissions = PermissionStatus()
    private var window: NSWindow?
    private var themeSink: AnyCancellable?

    init(host: PanelHost) {
        self.host = host
    }

    func show() {
        let window = self.window ?? make()
        self.window = window
        permissions.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let root = SettingsView(host: host, user: host.user, theme: host.theme, permissions: permissions)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Den Den Settings"
        window.contentView = NSHostingView(rootView: root)
        window.contentMinSize = NSSize(width: 480, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("DenDenSettings")
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
                        Button("Open denden.toml") { openSettingsFile() }
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

                let issues = host.allIssues
                if !issues.isEmpty {
                    Section {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                                    .foregroundStyle(theme.muted)
                                Text(issue.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.foreground)
                                    .textSelection(.enabled)
                            }
                        }
                    } header: {
                        SettingsHeader(text: "Problems", note: "Files Den Den could not fully read. The rest keeps working.")
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
                Text("When the pointer rests on the notch").tag(DenDenSettings.OpenOn.hover)
                Text("When the notch is clicked").tag(DenDenSettings.OpenOn.click)
            }
            Picker("Show on", selection: Binding(
                get: { host.settings.externalDisplays },
                set: { failure = host.save("external_displays", .string($0.rawValue)) })) {
                Text("The built-in display").tag(DenDenSettings.ExternalDisplays.none)
                Text("Every display (a pill where there is no notch)").tag(DenDenSettings.ExternalDisplays.pill)
            }
            settingToggle("Artwork and playing bars beside the closed notch", key: "live_activity", value: host.settings.liveActivity)
            settingToggle("Den Den in the menu bar", key: "menu_bar_icon", value: host.settings.menuBarIcon)
            settingToggle("Open at login", key: "launch_at_login", value: host.settings.launchAtLogin)
        }
        .font(.system(size: 13))
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
        return "Widget from \(file), runs \(w.refresh.description)."
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
            return "Hidden: Den Den may not read \(permission.name). Allow it in System Settings, Privacy & Security, \(permission.name)."
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
