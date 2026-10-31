import AppKit

/// The Settings windows of the file browser and the launcher: each opens
/// from its shortcut and its URL, shows every pane from the sidebar, flips one
/// harmless option and back, and keeps its layout (sidebar on the left, the
/// pane beside it, nothing clipped).
enum SettingsJourneys {
    static var all: [Journey] { [files, launcher] }

    static let filesPanes = ["general", "sidebar", "tags", "views", "search", "appearance", "advanced"]
    static let launcherPanes = ["general", "sources", "search", "web", "appearance", "advanced"]

    static func journey(_ name: String, role: String, summary: String, waitsForWindow: Bool, _ steps: [Step]) -> Journey {
        Journey(name, role: role, summary: summary, waitsForWindow: waitsForWindow,
                window: { ctx in ctx.appSettingsWindow() }, rules: rules, steps: steps)
    }

    // MARK: Files

    static var files: Journey {
        var steps: [Step] = [
            step("open Settings with Cmd+,") { ctx in
                ctx.activate()
                _ = try ctx.mainWindow()
                try ctx.key("cmd+,")
                try ctx.waitForSettings()
                if let window = ctx.appSettingsWindow() {
                    window.move(to: CGPoint(x: 80, y: 80))
                    window.resize(to: CGSize(width: 780, height: 580))
                }
            },
        ]
        steps += filesPanes.map { pane in step("pane: \(pane)") { ctx in try ctx.openSettingsPane(pane) } }
        steps += [
            step("General: hide the status bar and show it again") { ctx in
                try ctx.openSettingsPane("general")
                let before = try ctx.settingValue("general.statusBar")
                try ctx.pressSetting("general.statusBar")
                try ctx.wait("the switch to turn \(before == "1" ? "off" : "on")") { (try? ctx.settingValue("general.statusBar")) != before }
                if before == "1" {
                    try ctx.wait("the browser window's status bar to go") { ctx.browserStatus() == nil }
                }
                try ctx.pressSetting("general.statusBar")
                try ctx.wait("the switch to return") { (try? ctx.settingValue("general.statusBar")) == before }
                if before == "1" {
                    try ctx.wait("the status bar to come back") { ctx.browserStatus() != nil }
                }
            },
            step("nexus://settings/search opens the Search pane") { ctx in
                try ctx.openSettingsPane("general")
                guard let scheme = ctx.app.urlScheme else { throw StepSkip("apps.tsv names no URL scheme for \(ctx.app.name)") }
                try ctx.openApp(["\(scheme)://settings/search"])
                try ctx.wait("the Search pane") { ctx.settingNode("search.pane") != nil }
            },
            step("Cmd+W closes Settings", layout: false) { ctx in
                try ctx.key("cmd+w")
                try ctx.wait("the Settings window to close") { ctx.appSettingsWindow() == nil }
            },
        ]
        return journey("files-settings", role: FilesJourneys.role, summary: "Settings opens, shows every pane, flips the status bar and back",
                       waitsForWindow: true, steps)
    }

    // MARK: Launcher

    static var launcher: Journey {
        var steps: [Step] = [
            step("open Settings from its URL (as \"sight settings\" does)") { ctx in
                guard let scheme = ctx.app.urlScheme else { throw StepSkip("apps.tsv names no URL scheme for \(ctx.app.name)") }
                try ctx.openApp(["\(scheme)://settings"])
                try ctx.waitForSettings()
                if let window = ctx.appSettingsWindow() {
                    window.move(to: CGPoint(x: 80, y: 80))
                    window.resize(to: CGSize(width: 780, height: 580))
                }
            },
        ]
        steps += launcherPanes.map { pane in step("pane: \(pane)") { ctx in try ctx.openSettingsPane(pane) } }
        steps += [
            step("General: close after a setting change, on and off") { ctx in
                try ctx.openSettingsPane("general")
                let before = try ctx.settingValue("general.closeAfterSetting")
                try ctx.pressSetting("general.closeAfterSetting")
                try ctx.wait("the switch to flip") { (try? ctx.settingValue("general.closeAfterSetting")) != before }
                try ctx.pressSetting("general.closeAfterSetting")
                try ctx.wait("the switch to return") { (try? ctx.settingValue("general.closeAfterSetting")) == before }
            },
            step("Cmd+, in the search window opens Settings", layout: false) { ctx in
                try ctx.key("cmd+w")
                try ctx.wait("the Settings window to close") { ctx.appSettingsWindow() == nil }
                try ctx.showPanel(metric: "time to visible")
                try ctx.key("cmd+,")
                try ctx.waitForSettings()
                try ctx.check(!ctx.panelVisible(), "the search window stayed open over Settings")
            },
            step("Cmd+W closes Settings", layout: false) { ctx in
                try ctx.key("cmd+w")
                try ctx.wait("the Settings window to close") { ctx.appSettingsWindow() == nil }
            },
        ]
        return journey("launcher-window-settings", role: LauncherJourneys.role,
                       summary: "Settings opens from its URL and Cmd+, shows every pane, flips one option and back",
                       waitsForWindow: false, steps)
    }

    // MARK: Layout

    /// The sidebar lists every pane at the window's left; the pane shown sits to its right.
    static func rules(_ ctx: Ctx, _ snap: Snapshot, _ window: CGRect) -> [String] {
        guard ctx.appSettingsWindow() != nil else { return [] }
        var problems: [String] = []
        let panes = ctx.app.role == FilesJourneys.role ? filesPanes : launcherPanes
        var sidebarRight: CGFloat = 0
        for pane in panes {
            guard let entry = snap.identified(ctx.app.id("settings.\(pane)")), let frame = entry.frame else {
                problems.append("no sidebar entry for \(pane)")
                continue
            }
            sidebarRight = max(sidebarRight, frame.maxX)
            if frame.minX - window.minX > 40 { problems.append("the \(pane) entry is \(Int(frame.minX - window.minX)) pt from the window's left") }
        }
        if let shown = snap.nodes.first(where: { $0.identifier.hasPrefix(ctx.app.id("settings.")) && $0.identifier.hasSuffix(".pane") }),
           let frame = shown.frame {
            if frame.minX < sidebarRight - 1 { problems.append("the pane \(Ctx.rect(frame)) overlaps the sidebar (right edge \(Int(sidebarRight)))") }
            if frame.width < 300 { problems.append("the pane is only \(Int(frame.width)) pt wide") }
        } else {
            problems.append("no pane is shown")
        }
        return problems
    }
}

extension Ctx {
    /// The app's Settings window, by its identifier or its title.
    func appSettingsWindow() -> Element? {
        windows().first { $0.string("AXIdentifier") == app.id("settings") || $0.title == "\(app.name) Settings" }
    }

    func waitForSettings() throws {
        try wait("the Settings window", timeout: 10) { self.appSettingsWindow() != nil }
    }

    func settingsSnapshot() -> Snapshot? { appSettingsWindow().map { snapshot($0) } }

    /// A control in the Settings window by its identifier, without the "<app>.settings." part.
    func settingNode(_ suffix: String) -> Node? {
        settingsSnapshot()?.identified(app.id("settings." + suffix))
    }

    func pressSetting(_ suffix: String) throws {
        guard let node = settingNode(suffix) else { throw StepFailure("no control \(app.id("settings." + suffix)) in Settings") }
        if !node.element.perform("AXPress") { try click(node) }
        Input.pause(0.2)
    }

    /// A switch's value: "1" on, "0" off.
    func settingValue(_ suffix: String) throws -> String {
        guard let node = settingNode(suffix) else { throw StepFailure("no control \(app.id("settings." + suffix)) in Settings") }
        return node.value
    }

    /// Clicks a pane's sidebar entry and waits for the pane.
    func openSettingsPane(_ pane: String) throws {
        try pressSetting(pane)
        try wait("the \(pane) pane") { self.settingNode("\(pane).pane") != nil }
    }

    /// The browser window's status bar count, whichever window is in front.
    func browserStatus() -> Int? {
        let browser = windows().first { $0.string("AXSubrole") == "AXStandardWindow" && $0.title != "\(app.name) Settings" }
        return browser.flatMap { FilesJourneys.statusCount(snapshot($0)) }
    }
}
