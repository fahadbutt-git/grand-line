import AppKit

/// The launcher (role "launcher"): open it, find a file, open it, answers,
/// web fallbacks, hide it, and the system settings it switches.
enum LauncherJourneys {
    static let role = "launcher"

    static var all: [Journey] { [openAndFiles, answers, settings] }

    static func journey(_ name: String, _ summary: String, fixtureHome: Bool = true, _ steps: [Step]) -> Journey {
        Journey(name, role: role, summary: summary, waitsForWindow: false, usesFixtureHome: fixtureHome,
                window: { ctx in ctx.panel() }, rules: rules, steps: steps)
    }

    static var openAndFiles: Journey {
        journey("launcher-open-files", "appears fast, finds a file as you type, Return opens it, Esc clears then hides", [
            step("let the name index of the fixture home build", layout: false) { _ in Input.pause(2) },
            step("open it (open -a, as a shortcut does) and time it") { ctx in try ctx.showPanel(metric: "time to visible") },
            step("type a file name prefix: first result time, in Files") { ctx in
                let ms = try ctx.time("conj_storyboard.pptx in the results", timeout: 10) {
                    if ctx.panelTexts().isEmpty { return false }
                    return ctx.panelTexts().contains { $0.hasPrefix("conj_storyboard") }
                } before: { ctx.type("conj_story") }
                ctx.metric("keystrokes to first result", ms)
                try ctx.check(ctx.panelTexts().contains("Files"), "no Files section; shown: \(ctx.panelTexts().prefix(20))")
            },
            step("Esc clears the field, a second Esc hides the panel") { ctx in
                try ctx.key("escape")
                try ctx.wait("the field to empty") { ctx.fieldText() == "" }
                try ctx.key("escape")
                try ctx.wait("the panel to hide") { !ctx.panelVisible() }
            },
            step("Return opens the file it found") { ctx in
                try ctx.showPanel(metric: "time to visible again")
                let before = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                ctx.type("conj notes.txt")
                try ctx.wait("conj notes.txt as a result") { ctx.panelTexts().contains { $0.hasPrefix("conj notes") } }
                try ctx.key("return")
                var opener: NSRunningApplication?
                try ctx.wait("an app showing conj notes.txt", timeout: 20) {
                    guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ctx.pid else { return false }
                    opener = front
                    let window = Element.app(front.processIdentifier).element("AXFocusedWindow")
                    return (window?.title ?? "").contains("conj notes")
                }
                if let opener, !before.contains(opener.processIdentifier) { ctx.opened.append(opener.processIdentifier) }
                try ctx.check(!ctx.panelVisible(), "the panel stayed open after opening the file")
            },
            step("hotkey (Command+Space) when the launcher owns it") { ctx in
                let defaults = Shell.run("/usr/bin/defaults", ["read", ctx.app.bundleID, "TakesCommandSpace"], timeout: 10)
                guard defaults.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" else {
                    throw StepSkip("Command+Space still belongs to Spotlight on this Mac (TakesCommandSpace is off)")
                }
                ctx.activate()
                let ms = try ctx.time("the panel after Command+Space", timeout: 5) { ctx.panelVisible() } before: { try? Input.press("cmd+space") }
                ctx.metric("hotkey to visible", ms)
                try ctx.key("escape"); try ctx.key("escape")
            },
        ])
    }

    static var answers: Journey {
        journey("launcher-answers", "calculator, unit conversion, web fallbacks, settings window if any", [
            step("open it") { ctx in try ctx.showPanel(metric: "time to visible") },
            step("calculator: 2+2") { ctx in
                ctx.type("2+2")
                try ctx.wait("the answer 4") { ctx.panelTexts().contains("4") }
                try ctx.check(ctx.panelTexts().contains("Answers"), "no Answers section")
            },
            step("unit conversion: 5km to m") { ctx in
                try ctx.replaceQuery("5km to m")
                try ctx.wait("5,000 m") { ctx.panelTexts().contains { $0.contains("5,000 m") || $0.contains("5000 m") } }
            },
            step("web fallback rows") { ctx in
                try ctx.replaceQuery("conj flap retraction")
                try ctx.wait("a fallback row for the words", timeout: 10) {
                    ctx.panelTexts().contains { $0.contains("conj flap retraction") && $0 != "conj flap retraction" }
                }
            },
            step("Esc, Esc hides it") { ctx in
                try ctx.key("escape"); try ctx.key("escape")
                try ctx.wait("the panel to hide") { !ctx.panelVisible() }
            },
            step("settings window, if the app has one", layout: false) { ctx in
                guard let bar = ctx.ax.element("AXExtrasMenuBar"),
                      let item = bar.children.first, item.perform("AXPress") else {
                    throw StepSkip("no menu bar icon menu to look in")
                }
                Input.pause(0.4)
                let entries = item.children.flatMap(\.children)
                guard let settings = entries.first(where: { $0.title.hasPrefix("Settings") || $0.title.hasPrefix("Preferences") }) else {
                    try? ctx.key("escape")
                    throw StepSkip("no settings window yet (menu: \(entries.map(\.title).filter { !$0.isEmpty }.joined(separator: ", ")))")
                }
                settings.perform("AXPress")
                try ctx.wait("a settings window") { ctx.windows().contains { $0.title.contains("Settings") || $0.title.contains("Preferences") } }
                ctx.shot("settings", window: ctx.windows().first { $0.title.contains("Settings") || $0.title.contains("Preferences") })
                try ctx.key("cmd+w")
            },
        ])
    }

    // MARK: System settings, one line each

    /// How to read a setting without the launcher, and what a run may do.
    struct Setting {
        enum Mode {
            /// Return flips it; checked against the system and flipped back.
            case toggle
            /// Return only asks first; checked that it asks and Esc cancels.
            case confirm
            /// Would end the session (lock, display sleep): only checked to be offered.
            case offerOnly
        }
        let id: String
        let phrase: String
        let mode: Mode
        /// A shell command that prints the current state. "SKIP <why>" skips
        /// the case on this Mac; nil means there is no independent reading.
        let read: String?
    }

    /// Add a setting here, with the row's identifier (setting.<id>).
    static let settingsTable: [Setting] = [
        Setting(id: "darkmode", phrase: "dark mode", mode: .toggle, read: "defaults read -g AppleInterfaceStyle 2>&1"),
        Setting(id: "wifi", phrase: "wi-fi", mode: .toggle, read: #"d=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2; exit}'); [ -n "$d" ] || { echo "SKIP no Wi-Fi hardware on this Mac"; exit 0; }; networksetup -getairportpower "$d""#),
        Setting(id: "bluetooth", phrase: "bluetooth", mode: .toggle, read: #"if command -v blueutil >/dev/null; then blueutil -p; else s=$(system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/State:/{print $2; exit}'); [ -n "$s" ] && echo "$s" || echo "SKIP no Bluetooth hardware on this Mac"; fi"#),
        Setting(id: "focus", phrase: "focus", mode: .toggle, read: nil),
        Setting(id: "mute", phrase: "mute", mode: .toggle, read: #"v=$(osascript -e 'output muted of (get volume settings)' 2>&1); case "$v" in true|false) echo "$v";; *) echo "SKIP no sound output on this Mac ($v)";; esac"#),
        Setting(id: "hiddenfiles", phrase: "hidden files", mode: .toggle, read: "defaults read com.apple.finder AppleShowAllFiles 2>&1"),
        Setting(id: "dockautohide", phrase: "dock autohide", mode: .toggle, read: "defaults read com.apple.dock autohide 2>&1"),
        Setting(id: "desktopicons", phrase: "desktop icons", mode: .toggle, read: #"v=$(defaults read com.apple.finder CreateDesktop 2>&1); case "$v" in *exist*) echo 1;; *) echo "$v";; esac"#),
        Setting(id: "menubarautohide", phrase: "menu bar autohide", mode: .toggle, read: "defaults read -g _HIHideMenuBar 2>&1"),
        Setting(id: "keepawake", phrase: "keep awake", mode: .toggle, read: "pmset -g assertions | grep -i -E 'byakugan|caffeinate' | grep -c -i prevent"),
        Setting(id: "lock", phrase: "lock screen", mode: .offerOnly, read: nil),
        Setting(id: "sleepdisplay", phrase: "sleep display", mode: .offerOnly, read: nil),
        Setting(id: "restart", phrase: "restart", mode: .confirm, read: nil),
        Setting(id: "sleep", phrase: "sleep", mode: .confirm, read: nil),
        Setting(id: "shutdown", phrase: "shut down", mode: .confirm, read: nil),
    ]

    static var settings: Journey {
        let steps = settingsTable.map { setting in
            step("\(setting.phrase) (setting.\(setting.id))", timeout: 60) { ctx in try ctx.exercise(setting) }
        }
        // The system's own settings are what is under test, so the real home.
        return journey("launcher-settings", "each system setting switched from the launcher, checked against the system", fixtureHome: false,
                       [step("let the launcher settle", layout: false) { _ in Input.pause(1.5) }] + steps)
    }

    /// "on" or "off" from what a read command printed; nil when it is a number or other value.
    static func normalise(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let last = text.split(whereSeparator: { $0 == " " || $0 == ":" }).last.map(String.init) ?? text
        if text.contains("does not exist") || text.isEmpty { return "off" }
        if ["dark", "on", "1", "true", "yes"].contains(last) { return "on" }
        if ["light", "off", "0", "false", "no"].contains(last) { return "off" }
        if let n = Int(last) { return n > 0 ? "on" : "off" }
        return text
    }

    // MARK: Layout

    static func rules(_ ctx: Ctx, _ snap: Snapshot, _ window: CGRect) -> [String] {
        guard ctx.panelVisible() else { return [] }
        guard let field = snap.first(nil, { Layout.inputRoles.contains($0.role) && $0.isVisibleSize }), let f = field.frame else {
            return ["no search field in the panel"]
        }
        return f.minY - window.minY > 70 ? ["the search field is \(Int(f.minY - window.minY)) pt below the top of the panel"] : []
    }
}

extension Ctx {
    /// The launcher's panel window, if it is on screen.
    func panel() -> Element? {
        guard panelVisible() else { return nil }
        return windows().first { ($0.frame?.height ?? 0) > 100 }
    }

    func panelVisible() -> Bool {
        Capture.windows(pid: pid).contains { $0.bounds.height > 100 }
    }

    func panelSnapshot() -> Snapshot? { panel().map { snapshot($0) } }

    func panelTexts() -> [String] { panelSnapshot()?.texts ?? [] }

    func fieldText() -> String? {
        panelSnapshot()?.first(nil) { Layout.inputRoles.contains($0.role) }?.value
    }

    func showPanel(metric name: String) throws {
        let ms = try time("the panel with its search field", timeout: 15) {
            self.panelVisible() && self.fieldText() != nil
        } before: { try? self.openApp() }
        metric(name, ms)
        try check(ms <= options.showLimit, "the panel took \(Int(ms)) ms to appear (limit \(Int(options.showLimit)) ms)")
        try wait("the field to take the keys") { self.isEditingText() }
    }

    func replaceQuery(_ text: String) throws {
        try key("cmd+a")
        type(text)
    }

    /// Times from an action to a condition.
    func time(_ what: String, timeout: TimeInterval, _ condition: () throws -> Bool, before action: () throws -> Void) throws -> Double {
        let start = Date()
        try action()
        try wait(what, timeout: timeout, poll: 0.01, condition)
        return Date().timeIntervalSince(start) * 1000
    }

    func readSetting(_ setting: LauncherJourneys.Setting) -> String? {
        guard let command = setting.read else { return nil }
        let out = Shell.run("/bin/sh", ["-c", command], timeout: 20).output.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    /// The row's own words (title and state), found by its identifier.
    func settingRow(_ id: String) -> (node: Node, text: String)? {
        guard let snap = panelSnapshot(), let index = snap.nodes.firstIndex(where: { $0.identifier == "setting." + id }) else { return nil }
        let words = ([snap.nodes[index]] + snap.descendants(of: index)).map(\.text).filter { !$0.isEmpty }
        return (snap.nodes[index], words.joined(separator: " "))
    }

    func showSetting(_ setting: LauncherJourneys.Setting) throws -> String {
        if !panelVisible() { try showPanel(metric: "time to visible (\(setting.id))") }
        try replaceQuery(setting.phrase)
        var text = ""
        try wait("a row setting.\(setting.id) for \"\(setting.phrase)\"") {
            guard let row = self.settingRow(setting.id) else { return false }
            text = row.text
            return true
        }
        return text
    }

    func exercise(_ setting: LauncherJourneys.Setting) throws {
        let first = readSetting(setting)
        if let first, first.hasPrefix("SKIP") { throw StepSkip(String(first.dropFirst(5))) }
        let rowBefore = try showSetting(setting)
        switch setting.mode {
        case .offerOnly:
            note("\(setting.phrase): offered; not run, it would end the session")
            try key("escape"); try key("escape")
            return
        case .confirm:
            let footer = Set(panelTexts())
            try key("return")
            try wait("the launcher to ask before it acts") { self.panelTexts().contains("cancel") && !footer.contains("cancel") }
            try key("escape")
            try wait("Esc to cancel the question") { !self.panelTexts().contains("cancel") }
            try check(panelVisible(), "the panel closed: did it act instead of asking?")
            try key("escape"); try key("escape")
            return
        case .toggle:
            break
        }
        let systemBefore = first.map(LauncherJourneys.normalise)
        var restored = false
        defer {
            // Leave the Mac as it was, whatever happened above.
            if !restored, let systemBefore, let now = readSetting(setting).map(LauncherJourneys.normalise), now != systemBefore {
                if (try? showSetting(setting)) != nil { try? key("return"); Input.pause(1.5) }
                if readSetting(setting).map(LauncherJourneys.normalise) != systemBefore {
                    note("\(setting.phrase) could not be put back to \(systemBefore)")
                }
            }
            try? key("escape"); try? key("escape")
        }
        func flip(_ label: String, from rowText: String, system: String?) throws -> (String, String?) {
            try key("return")
            var newSystem = system
            if let system {
                try wait("\(setting.phrase) to change in the system (\(label))", timeout: 10) {
                    newSystem = self.readSetting(setting).map(LauncherJourneys.normalise)
                    return newSystem != nil && newSystem != system
                }
            }
            let rowText2 = try showSetting(setting)
            var latest = rowText2
            try wait("the row's state to change (\(label)): was \"\(rowText)\"") {
                latest = self.settingRow(setting.id)?.text ?? latest
                return latest != rowText
            }
            return (latest, newSystem)
        }
        let (rowOn, systemOn) = try flip("first Return", from: rowBefore, system: systemBefore)
        let (rowBack, systemBack) = try flip("second Return", from: rowOn, system: systemOn)
        try check(rowBack == rowBefore, "the row reads \"\(rowBack)\" after switching back, \"\(rowBefore)\" before")
        if let systemBefore { try check(systemBack == systemBefore, "the system reads \(systemBack ?? "?") after switching back, \(systemBefore) before") }
        if setting.read == nil { note("\(setting.phrase): only the row was checked, there is no independent reading") }

        // A fast double Return must switch it once, not twice.
        _ = try showSetting(setting)
        try Input.press("return")
        Input.pause(0.03)
        try Input.press("return")
        Input.pause(2)
        if let systemBefore {
            let now = readSetting(setting).map(LauncherJourneys.normalise)
            try check(now != systemBefore, "a fast double Return switched \(setting.phrase) twice (it reads \(now ?? "?") again)")
        }
        let rowNow = try showSetting(setting)
        try check(rowNow != rowBefore, "after a fast double Return the row reads as before: \"\(rowNow)\"")
        // And back.
        _ = try flip("back after the double Return", from: rowNow, system: readSetting(setting).map(LauncherJourneys.normalise))
        restored = true
    }
}
