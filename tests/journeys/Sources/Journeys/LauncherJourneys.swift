import AppKit

/// The launcher (role "launcher"): open it, find a file, open it, answers,
/// web fallbacks, hide it, and the system settings it switches.
enum LauncherJourneys {
    static let role = "launcher"

    static var all: [Journey] { [openAndFiles, answers, actions, fallbacks, settings] }

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
            // An answer is the best match for what was typed, so it leads as the
            // Top hit; with other results above it, it sits under Answers.
            step("calculator: 2+2") { ctx in
                ctx.type("2+2")
                try ctx.wait("the answer 4") { ctx.panelTexts().contains("4") }
                try ctx.check(ctx.answerSection(for: { $0 == "4" }) != nil, "4 is in neither the Top hit nor an Answers section")
            },
            step("unit conversion: 5km to m") { ctx in
                try ctx.replaceQuery("5km to m")
                let isAnswer: (String) -> Bool = { $0.contains("5,000 m") || $0.contains("5000 m") }
                try ctx.wait("5,000 m") { ctx.panelTexts().contains(where: isAnswer) }
                try ctx.check(ctx.answerSection(for: isAnswer) != nil, "5,000 m is in neither the Top hit nor an Answers section")
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

    /// Command+K on a file row: the panel lists every file action, Escape
    /// closes it and keeps the query, a shortcut and a click run an action.
    static var actions: Journey {
        journey("launcher-actions", "Command+K lists the file actions; a shortcut and a click run them", [
            step("let the name index of the fixture home build", layout: false) { _ in Input.pause(2) },
            step("open it and find conj notes.txt") { ctx in
                try ctx.showPanel(metric: "time to visible")
                ctx.type("conj notes")
                try ctx.wait("conj notes.txt as a result", timeout: 10) { ctx.panelTexts().contains { $0.hasPrefix("conj notes") } }
            },
            step("Command+K opens the action panel with the file actions") { ctx in
                try ctx.key("cmd+k")
                let wanted = ["action.open-with", "action.show-in-nexus", "action.quick-look", "action.copy-path",
                              "action.copy-name", "action.add-to-buffer", "action.move-to-trash"]
                try ctx.wait("the action panel") { ctx.panelIdentifiers().contains("action.copy-name") }
                let shown = ctx.panelIdentifiers()
                let missing = wanted.filter { !shown.contains($0) }
                try ctx.check(missing.isEmpty, "the panel lacks \(missing.joined(separator: ", "))")
                try ctx.check(!shown.contains { $0.contains("delete") }, "the panel offers to delete a file")
            },
            step("Escape closes the panel and keeps the query") { ctx in
                try ctx.key("escape")
                try ctx.wait("the panel to close") { !ctx.panelIdentifiers().contains("action.copy-name") }
                try ctx.check(ctx.panelVisible(), "Escape closed the window instead of the action panel")
                try ctx.check((ctx.fieldText() ?? "").contains("conj notes"), "the query was cleared: \(ctx.fieldText() ?? "")")
            },
            step("Option+Command+C copies the path without opening the panel") { ctx in
                NSPasteboard.general.clearContents()
                try ctx.key("opt+cmd+c")
                try ctx.wait("the path on the clipboard") {
                    (NSPasteboard.general.string(forType: .string) ?? "").hasSuffix("/conj notes.txt")
                }
            },
            step("clicking Copy name in the panel copies the name") { ctx in
                // Copy path closed the window.
                if !ctx.panelVisible() { try ctx.showPanel(metric: "time to visible again") }
                try ctx.replaceQuery("conj notes")
                try ctx.wait("conj notes.txt as a result", timeout: 10) { ctx.panelTexts().contains { $0.hasPrefix("conj notes") } }
                NSPasteboard.general.clearContents()
                try ctx.key("cmd+k")
                try ctx.wait("the action panel") { ctx.panelIdentifiers().contains("action.copy-name") }
                guard let node = ctx.panelSnapshot()?.first(nil, { $0.identifier == "action.copy-name" }) else {
                    throw StepFailure("no Copy name action to click")
                }
                try ctx.click(node)
                try ctx.wait("the name on the clipboard") { NSPasteboard.general.string(forType: .string) == "conj notes.txt" }
            },
            step("Move to Trash asks first, and Escape leaves the file alone", layout: false) { ctx in
                if !ctx.panelVisible() { try ctx.showPanel(metric: "time to visible again") }
                try ctx.replaceQuery("conj notes")
                try ctx.wait("conj notes.txt as a result", timeout: 10) { ctx.panelTexts().contains { $0.hasPrefix("conj notes") } }
                try ctx.key("cmd+k")
                try ctx.wait("the action panel") { ctx.panelIdentifiers().contains("action.move-to-trash") }
                guard let node = ctx.panelSnapshot()?.first(nil, { $0.identifier == "action.move-to-trash" }) else {
                    throw StepFailure("no Move to Trash action")
                }
                try ctx.click(node)
                try ctx.wait("the question in the footer") { ctx.panelTexts().contains("cancel") }
                try ctx.key("escape")
                try ctx.wait("Esc to cancel the question") { !ctx.panelTexts().contains("cancel") }
                let found = FileManager.default.enumerator(atPath: ctx.home.path)?
                    .contains { ($0 as? String)?.hasSuffix("conj notes.txt") == true } ?? false
                try ctx.check(found, "conj notes.txt is gone although the question was cancelled")
                try ctx.key("escape"); try ctx.key("escape"); try ctx.key("escape")
            },
        ])
    }

    /// Nothing matches: the web engines, Create file in Downloads and Run in
    /// Terminal are offered; creating works, and running asks first.
    static var fallbacks: Journey {
        journey("launcher-fallback", "with no match, Create file makes it in Downloads and Run in Terminal asks first", [
            step("open it and type words nothing matches") { ctx in
                try ctx.showPanel(metric: "time to visible")
                ctx.type("qzxv journey note")
                try ctx.wait("the fallback rows", timeout: 10) {
                    let ids = ctx.panelIdentifiers()
                    return ids.contains("fallback:create-file") && ids.contains("fallback:run-terminal")
                }
                try ctx.check(ctx.panelTexts().contains { $0.hasPrefix("Search") && $0.contains("qzxv journey note") },
                              "no web engine row for the words")
            },
            step("Run in Terminal asks before it runs") { ctx in
                guard let node = ctx.panelSnapshot()?.first(nil, { $0.identifier == "fallback:run-terminal" }) else {
                    throw StepFailure("no Run in Terminal row")
                }
                try ctx.click(node)
                try ctx.wait("the question in the footer") { ctx.panelTexts().contains("cancel") }
                try ctx.key("escape")
                try ctx.wait("Esc to cancel the question") { !ctx.panelTexts().contains("cancel") }
                try ctx.check(ctx.panelVisible(), "the window closed: did it run the words?")
            },
            step("Create file makes an empty file in Downloads") { ctx in
                let file = ctx.home.appendingPathComponent("Downloads/qzxv journey note")
                try? FileManager.default.removeItem(at: file)
                guard let node = ctx.panelSnapshot()?.first(nil, { $0.identifier == "fallback:create-file" }) else {
                    throw StepFailure("no Create file row")
                }
                try ctx.click(node)
                try ctx.wait("the new file in Downloads") { FileManager.default.fileExists(atPath: file.path) }
                let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
                try ctx.check(size == 0, "the new file is not empty (\(size) bytes)")
                try? FileManager.default.removeItem(at: file)
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
        Setting(id: "wifi", phrase: "wifi", mode: .toggle, read: #"d=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2; exit}'); [ -n "$d" ] || { echo "SKIP no Wi-Fi hardware on this Mac"; exit 0; }; networksetup -getairportpower "$d""#),
        Setting(id: "bluetooth", phrase: "bluetooth", mode: .toggle, read: #"if command -v blueutil >/dev/null; then blueutil -p; else s=$(system_profiler SPBluetoothDataType 2>/dev/null | awk -F': ' '/State:/{print $2; exit}'); [ -n "$s" ] && echo "$s" || echo "SKIP no Bluetooth hardware on this Mac"; fi"#),
        Setting(id: "dnd", phrase: "do not disturb", mode: .toggle, read: nil),
        Setting(id: "mute", phrase: "mute", mode: .toggle, read: #"v=$(osascript -e 'output muted of (get volume settings)' 2>&1); case "$v" in true|false) echo "$v";; *) echo "SKIP no sound output on this Mac ($v)";; esac"#),
        Setting(id: "hiddenfiles", phrase: "hidden files", mode: .toggle, read: "defaults read com.apple.finder AppleShowAllFiles 2>&1"),
        Setting(id: "dockautohide", phrase: "dock autohide", mode: .toggle, read: "defaults read com.apple.dock autohide 2>&1"),
        Setting(id: "desktopicons", phrase: "desktop icons", mode: .toggle, read: #"v=$(defaults read com.apple.finder CreateDesktop 2>&1); case "$v" in *exist*) echo 1;; *) echo "$v";; esac"#),
        Setting(id: "menubarautohide", phrase: "menu bar autohide", mode: .toggle, read: "defaults read -g _HIHideMenuBar 2>&1"),
        Setting(id: "keepawake", phrase: "keep awake", mode: .toggle, read: "pmset -g assertions | grep -i -E 'sight|caffeinate' | grep -c -i prevent"),
        Setting(id: "lock", phrase: "lock screen", mode: .offerOnly, read: nil),
        Setting(id: "displaysleep", phrase: "sleep display", mode: .offerOnly, read: nil),
        Setting(id: "restart", phrase: "restart", mode: .confirm, read: nil),
        Setting(id: "sleep", phrase: "sleep", mode: .confirm, read: nil),
        Setting(id: "shutdown", phrase: "shut down", mode: .confirm, read: nil),
        Setting(id: "logout", phrase: "log out", mode: .confirm, read: nil),
    ]

    /// The launcher's section headings, to tell which one a row sits under.
    static let headings: Set<String> = [
        "Favourites", "Recent", "Top hit", "Answers", "Apps", "Grand Line", "Windows", "System",
        "Bookmarks", "Snippets", "Symbols", "Files", "Web", "Other actions",
    ]

    static var settings: Journey {
        // Up to 10 s for the system to change, then up to the slowest change's
        // own limit (30 s) for the row to say why it did not.
        let steps = settingsTable.map { setting in
            step("\(setting.phrase) (setting.\(setting.id))", timeout: 120) { ctx in try ctx.exercise(setting) }
        }
        // The system's own settings are what is under test, so the real home.
        return journey("launcher-settings", "each system setting switched from the launcher, checked against the system", fixtureHome: false,
                       [step("let the launcher settle", layout: false) { _ in Input.pause(1.5) }] + steps)
    }

    /// The launcher's own words when macOS refused Automation for System Events,
    /// which a test machine cannot grant. Reported as a skip (a notice in CI,
    /// never a pass); any other failure stays a failure.
    static let automationRefused = "Automation not allowed"

    static func skipIfAutomationRefused(_ setting: Setting, row: String) throws {
        // Runners have no Bluetooth or Wi-Fi radio to switch: a plain
        // "Failed" there is the hardware, reported as a skip in CI only.
        // Do Not Disturb needs two Shortcuts the owner makes once (README),
        // which a runner does not have.
        let ciReason: [String: String] = ["bluetooth": "has no Bluetooth hardware", "wifi": "has no Wi-Fi hardware",
                                          "dnd": "has no Do Not Disturb shortcuts (made once by hand, see README)",
                                          "mute": "has no sound output device"]
        if let reason = ciReason[setting.id], ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil,
           row.lowercased().trimmingCharacters(in: .whitespaces) == "failed" {
            print("::notice title=\(setting.phrase) not checked::this CI runner \(reason); the row reads \(noticeText(row))")
            throw StepSkip("this CI runner \(reason); the row reads \"\(row)\"")
        }
        if setting.id == "darkmode" {
            try skipIfAppearanceLocked(setting, row: row, environment: ProcessInfo.processInfo.environment)
            return
        }
        guard row.contains(automationRefused) else { return }
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil {
            print("::notice title=\(setting.phrase) not checked::\(automationRefused) for System Events on this Mac; the row reads \"\(row)\"")
        }
        throw StepSkip("\(automationRefused) for System Events on this Mac, so \(setting.phrase) could not be switched; the row reads \"\(row)\"")
    }

    /// Dark mode on a GitHub runner: with no logged-in person's session behind
    /// it, macOS there can keep its appearance whatever asks, or refuse System
    /// Events. Only then, and only in CI, is it a reported skip (a notice with
    /// the row's words) and the other settings go on; anywhere else, or for
    /// any other reason, the step fails as it did.
    static func skipIfAppearanceLocked(_ setting: Setting, row: String, environment: [String: String]) throws {
        guard environment["GITHUB_ACTIONS"] != nil else { return }
        let lower = row.lowercased()
        // The row's value may be just "Failed" (its reason sits in another
        // line the snapshot does not join), which for dark mode on a runner
        // means the same: the command ran and macOS kept its appearance.
        let kept = (lower.contains("macos kept the") && lower.contains("appearance"))
            || lower.trimmingCharacters(in: .whitespaces) == "failed"
        guard kept || row.contains(automationRefused) else { return }
        print("::notice title=\(setting.phrase) not checked::\(noticeText(row))")
        throw StepSkip("macOS on this CI runner did not switch its appearance (\(kept ? "it kept the one it had" : automationRefused + " for System Events")); the row reads \"\(row)\"")
    }

    /// Text for a workflow command's message: %, CR and LF escaped.
    static func noticeText(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "\r", with: "%0D").replacingOccurrences(of: "\n", with: "%0A")
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
    /// The launcher's panel window, if it is on screen: not its Settings window.
    func panel() -> Element? {
        guard panelVisible() else { return nil }
        return windows().first { window in
            (window.frame?.height ?? 0) > 100 && window.string("AXIdentifier") != app.id("settings")
                && window.title != "\(app.name) Settings"
        }
    }

    /// Whether the search panel is on screen. It floats above normal windows
    /// (a window level above 0), which tells it from the Settings window.
    func panelVisible() -> Bool {
        Capture.windows(pid: pid).contains { $0.bounds.height > 100 && $0.layer > 0 }
    }

    func panelSnapshot() -> Snapshot? { panel().map { snapshot($0) } }

    func panelTexts() -> [String] { panelSnapshot()?.texts ?? [] }

    /// The accessibility identifiers on screen: action panel rows ("action.copy-name"),
    /// settings rows and the rows offered when nothing matches.
    func panelIdentifiers() -> [String] {
        panelSnapshot()?.nodes.map(\.identifier).filter { !$0.isEmpty } ?? []
    }

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

    /// "Top hit" or "Answers": the section heading that comes before the
    /// first text the test accepts, with no other heading between them.
    func answerSection(for isAnswer: (String) -> Bool) -> String? {
        let texts = panelTexts()
        guard let at = texts.firstIndex(where: isAnswer) else { return nil }
        let heading = texts[..<at].last { LauncherJourneys.headings.contains($0) }
        return heading.flatMap { ["Top hit", "Answers"].contains($0) ? $0 : nil }
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
        // Return runs the top hit: it should be this row, not the menu's copy
        // of it (a wrong row shows as the panel closing after Return, below).
        let heading = answerSection { !$0.isEmpty && ($0 == text || text.hasPrefix($0)) }
        if heading != "Top hit" {
            note("setting.\(setting.id) is not under Top hit for \"\(setting.phrase)\" (\(heading ?? "another heading"))")
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
                var refused: String?
                do {
                    try wait("\(setting.phrase) to change in the system (\(label))", timeout: 10) {
                        newSystem = self.readSetting(setting).map(LauncherJourneys.normalise)
                        if newSystem != nil && newSystem != system { return true }
                        // The row says at once when macOS refused the change.
                        if let row = self.settingRow(setting.id)?.text, row.contains("not changed") {
                            refused = row
                            return true
                        }
                        return false
                    }
                } catch let failure as StepFailure where failure.message.hasPrefix("timed out") {
                    // Still not changed: report what the row says once it has
                    // given up (a privacy prompt nobody can answer, a refusal).
                    var row = settingRow(setting.id)?.text ?? ""
                    try? wait("the row to finish (\(label))", timeout: 35, poll: 0.5) {
                        if self.readSetting(setting).map(LauncherJourneys.normalise).map({ $0 != system }) == true { return true }
                        row = self.settingRow(setting.id)?.text ?? row
                        return !row.contains("Working") && !row.isEmpty
                    }
                    newSystem = readSetting(setting).map(LauncherJourneys.normalise)
                    if newSystem == nil || newSystem == system {
                        try LauncherJourneys.skipIfAutomationRefused(setting, row: row)
                        // Return on a settings row keeps the panel open; a closed
                        // panel means another row (a menu or shortcut copy) ran.
                        let why = !row.isEmpty ? "; the row reads \"\(row)\""
                            : panelVisible() ? "; the row is not shown" : "; the panel closed after Return, so a row other than setting.\(setting.id) ran"
                        throw StepFailure(failure.message + why)
                    }
                    note("\(setting.phrase) took more than 10 s to change (\(label))")
                }
                if let refused {
                    try LauncherJourneys.skipIfAutomationRefused(setting, row: refused)
                    throw StepFailure("\(setting.phrase) was not changed (\(label)); the row reads \"\(refused)\"")
                }
            }
            let rowText2 = try showSetting(setting)
            try LauncherJourneys.skipIfAutomationRefused(setting, row: rowText2)
            var latest = rowText2
            try wait("the row's state to change (\(label)): was \"\(rowText)\"") {
                latest = self.settingRow(setting.id)?.text ?? latest
                return latest != rowText
            }
            return (latest, newSystem)
        }
        let (rowOn, systemOn) = try flip("first Return", from: rowBefore, system: systemBefore)
        // A row that turned "Failed" on the first Return (a setting a runner
        // cannot switch) ends the check here, as a reported skip in CI.
        try LauncherJourneys.skipIfAutomationRefused(setting, row: rowOn)
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
