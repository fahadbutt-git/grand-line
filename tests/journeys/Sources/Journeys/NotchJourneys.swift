import AppKit

/// The notch app (role "notch"): the panel opens from its URL commands and on
/// hover, shows only the sections turned on, has settings if it has them,
/// follows the theme, runs a signal widget when `iceberg trigger` asks, and
/// takes saved config files without a restart. Without a notch (CI) it sits
/// as a pill at the top.
enum NotchJourneys {
    static let role = "notch"

    static var all: [Journey] { [panel, settings, theme, signal, reload] }

    static func journey(_ name: String, _ summary: String, _ steps: [Step]) -> Journey {
        Journey(name, role: role, summary: summary, waitsForWindow: false,
                window: { ctx in ctx.notchWindow() }, steps: [placed] + steps)
    }

    static let placed = step("the closed panel sits at the top of a screen") { ctx in
        try ctx.wait("its window on screen", timeout: 15) { ctx.notchFrame() != nil }
        let frame = ctx.notchFrame()!
        let screens = NSScreen.screens.map { s -> CGRect in
            // Window-server coordinates have their origin at the top left of the main screen.
            let main = NSScreen.screens.first?.frame.height ?? s.frame.height
            return CGRect(x: s.frame.minX, y: main - s.frame.maxY, width: s.frame.width, height: s.frame.height)
        }
        try ctx.check(screens.contains { abs(frame.minY - $0.minY) < 4 && $0.intersects(frame) },
                      "the closed panel \(Ctx.rect(frame)) is not at the top of any screen \(screens.map { Ctx.rect($0) })")
        ctx.closedFrame = frame
    }

    static var panel: Journey {
        journey("notch-panel", "open and close by URL, only the turned-on sections, open on hover", [
            step("open (scheme://open)") { ctx in
                try ctx.notchURL("open")
                try ctx.wait("the panel to open") { ctx.isNotchOpen() }
                try ctx.wait("the Journey widget's output", timeout: 10) { ctx.notchTexts().contains { $0.contains("journey-ok") } }
            },
            step("only the sections turned on are shown") { ctx in
                let texts = ctx.notchTexts()
                try ctx.check(texts.contains("Journey"), "the Journey widget's title is missing; shown: \(texts)")
                for off in ["Today", "Reminders"] {
                    try ctx.check(!texts.contains(off), "\"\(off)\" shows although iceberg.toml leaves it out; shown: \(texts)")
                }
            },
            step("close (scheme://close)") { ctx in
                try ctx.notchURL("close")
                try ctx.wait("the panel to close") { !ctx.isNotchOpen() }
            },
            step("toggle twice (scheme://toggle)") { ctx in
                try ctx.notchURL("toggle")
                try ctx.wait("toggle to open it") { ctx.isNotchOpen() }
                try ctx.notchURL("toggle")
                try ctx.wait("toggle to close it") { !ctx.isNotchOpen() }
            },
            step("hover opens it, moving away closes it") { ctx in
                guard let closed = ctx.notchFrame() else { throw StepFailure("no panel window") }
                Input.move(to: CGPoint(x: closed.midX, y: closed.midY))
                Input.move(to: CGPoint(x: closed.midX + 1, y: closed.midY + 1))
                try ctx.wait("hover to open the panel", timeout: 5) { ctx.isNotchOpen() }
                let open = ctx.notchFrame() ?? closed
                Input.move(to: CGPoint(x: open.midX, y: open.maxY + 300))
                try ctx.wait("the panel to close when the pointer leaves", timeout: 5) { !ctx.isNotchOpen() }
            },
        ])
    }

    static var settings: Journey {
        journey("notch-settings", "the settings window opens, if the app has one", [
            step("open settings (scheme://settings)") { ctx in
                let before = ctx.windows().count
                try ctx.notchURL("settings")
                do {
                    try ctx.wait("a settings window", timeout: 6) {
                        ctx.windows().count > before || ctx.windows().contains { $0.title.contains("Settings") }
                    }
                } catch {
                    throw StepSkip("no settings window opened from scheme://settings (not built yet?)")
                }
                ctx.settingsWindow = ctx.windows().first { $0.title.contains("Settings") } ?? ctx.windows().last
                if let frame = ctx.settingsWindow?.frame, let window = ctx.settingsWindow {
                    let problems = Layout.generic(ctx.snapshot(window), window: frame)
                    try ctx.check(problems.isEmpty, "settings layout: " + problems.prefix(5).joined(separator: "; "))
                }
                ctx.shot("settings window", window: ctx.settingsWindow)
            },
        ])
    }

    static var theme: Journey {
        journey("notch-theme", "switching the theme state file recolours the open panel", [
            step("open the panel in the dark theme") { ctx in
                try ctx.notchURL("open")
                try ctx.wait("the panel to open") { ctx.isNotchOpen() }
                try ctx.wait("its widgets", timeout: 10) { ctx.notchTexts().contains { $0.contains("journey-ok") } }
            },
            step("switch to the light theme", layout: false) { ctx in
                guard Capture.canRecordScreen else { throw StepSkip("no Screen Recording permission, so colours cannot be compared") }
                Input.pause(0.6)
                let dark = ctx.dir.appendingPathComponent("theme-dark.png")
                guard Capture.shot(to: dark, window: ctx.notchWindowID()), let before = Capture.meanColour(of: dark) else {
                    throw StepFailure("could not capture the panel")
                }
                let state = ctx.home.appendingPathComponent(".local/state/grand-line/theme")
                try "daylight\n".write(to: state, atomically: true, encoding: .utf8)
                let light = ctx.dir.appendingPathComponent("theme-light.png")
                var after: Capture.Colour?
                try ctx.wait("the panel's colours to change", timeout: 8, poll: 0.5) {
                    guard Capture.shot(to: light, window: ctx.notchWindowID()), let colour = Capture.meanColour(of: light) else { return false }
                    after = colour
                    return colour.distance(to: before) > 0.15
                }
                ctx.note(String(format: "panel brightness %.2f in the dark theme, %.2f in the light one", before.luminance, after?.luminance ?? 0))
                try ctx.check((after?.luminance ?? 0) > before.luminance, "the light theme made the panel darker")
            },
            step("and back to the dark theme", layout: false) { ctx in
                let state = ctx.home.appendingPathComponent(".local/state/grand-line/theme")
                try "graphite\n".write(to: state, atomically: true, encoding: .utf8)
                // The theme is back either way; without Screen Recording the
                // colours were not compared, which is a skip, not a pass.
                guard Capture.canRecordScreen else { throw StepSkip("no Screen Recording permission, so colours cannot be compared") }
                let back = ctx.dir.appendingPathComponent("theme-back.png")
                let light = Capture.meanColour(of: ctx.dir.appendingPathComponent("theme-light.png"))
                try ctx.wait("the panel to darken again", timeout: 8, poll: 0.5) {
                    guard let light, Capture.shot(to: back, window: ctx.notchWindowID()), let colour = Capture.meanColour(of: back) else { return false }
                    return colour.luminance < light.luminance - 0.1
                }
            },
        ])
    }
}

extension NotchJourneys {
    /// A widget with `signal = true` that shows the contents of a file, so a
    /// step can change the file and then send the signal. The file is kept
    /// outside the config folder, where hot reload would run the widget by itself.
    static var signal: Journey {
        journey("notch-signal", "a signal widget runs when `iceberg trigger` or scheme://trigger asks, open or closed", [
            step("add a signal widget and put it in the panel (iceberg.toml saved in place)") { ctx in
                try ctx.writeHomeFile("signal-value.txt", "signal-1\n")
                try ctx.writeWidgetFile("signal.toml", """
                title = "Signal"
                icon = "bolt"
                command = 'cat "$HOME/signal-value.txt"'
                signal = true
                """)
                try ctx.editSettings { $0.replacingOccurrences(of: "panel = [\"battery\", \"journey\"]",
                                                                 with: "panel = [\"battery\", \"journey\", \"signal\"]") }
                try ctx.notchURL("open")
                try ctx.wait("the panel to open") { ctx.isNotchOpen() }
                try ctx.wait("the Signal widget's first value", timeout: 10) { ctx.notchTexts().contains { $0.contains("signal-1") } }
            },
            step("iceberg trigger runs it while the panel is open") { ctx in
                let pid = ctx.pid
                try ctx.writeHomeFile("signal-value.txt", "signal-2\n")
                Input.pause(0.5)
                try ctx.check(ctx.notchTexts().contains { $0.contains("signal-1") }, "the widget ran before it was triggered")
                try ctx.icebergCommand(["trigger", "signal"])
                try ctx.wait("the triggered value", timeout: 6) { ctx.notchTexts().contains { $0.contains("signal-2") } }
                try ctx.check(ctx.pid == pid && ctx.running?.isTerminated == false, "Iceberg restarted")
            },
            step("a trigger while closed runs it as the panel next opens") { ctx in
                try ctx.notchURL("close")
                try ctx.wait("the panel to close") { !ctx.isNotchOpen() }
                try ctx.writeHomeFile("signal-value.txt", "signal-3\n")
                try ctx.icebergCommand(["trigger", "signal"])
                try ctx.notchURL("open")
                try ctx.wait("the panel to open") { ctx.isNotchOpen() }
                try ctx.wait("the value from the trigger", timeout: 6) { ctx.notchTexts().contains { $0.contains("signal-3") } }
            },
            step("scheme://trigger/NAME works too") { ctx in
                try ctx.writeHomeFile("signal-value.txt", "signal-4\n")
                try ctx.notchURL("trigger/signal")
                try ctx.wait("the value from the URL", timeout: 6) { ctx.notchTexts().contains { $0.contains("signal-4") } }
                try ctx.notchURL("close")
            },
        ])
    }

    /// Hot reload: widget files and iceberg.toml saved while the panel is open.
    static var reload: Journey {
        journey("notch-reload", "saving a widget file or iceberg.toml updates the open panel without a restart", [
            step("open the panel") { ctx in
                try ctx.notchURL("open")
                try ctx.wait("the panel to open") { ctx.isNotchOpen() }
                try ctx.wait("the Journey widget's output", timeout: 10) { ctx.notchTexts().contains { $0.contains("journey-ok") } }
            },
            step("a widget file saved in place reloads it") { ctx in
                let pid = ctx.pid
                try ctx.writeWidgetFile("journey.toml", """
                title = "Journey"
                icon = "checkmark.circle"
                command = "echo journey-reloaded"
                refresh = "on open"
                """, inPlace: true)
                try ctx.wait("the new command's output", timeout: 6) { ctx.notchTexts().contains { $0.contains("journey-reloaded") } }
                try ctx.check(ctx.pid == pid && ctx.running?.isTerminated == false, "Iceberg restarted")
            },
            step("a save with a mistake keeps the last good version") { ctx in
                try ctx.writeWidgetFile("journey.toml", "title = \"Journey\"\ncommand = \"echo broken\n", inPlace: true)
                Input.pause(1.5)
                let texts = ctx.notchTexts()
                try ctx.check(texts.contains("Journey") && texts.contains("journey-reloaded"),
                              "the widget went away while its file had a mistake; shown: \(texts)")
            },
            step("fixing the file applies at once") { ctx in
                try ctx.writeWidgetFile("journey.toml", """
                title = "Journey"
                icon = "checkmark.circle"
                command = "echo journey-ok"
                refresh = "on open"
                """, inPlace: true)
                try ctx.wait("the fixed command's output", timeout: 6) { ctx.notchTexts().contains { $0.contains("journey-ok") } }
            },
            step("a new widget file and iceberg.toml saved in place show it") { ctx in
                try ctx.writeWidgetFile("second.toml", """
                title = "Second"
                icon = "2.circle"
                command = "echo second-ok"
                """)
                Input.pause(0.5)
                try ctx.check(!ctx.notchTexts().contains { $0.contains("second-ok") }, "a widget not in panel = [...] is shown")
                try ctx.editSettings { $0.replacingOccurrences(of: "panel = [\"battery\", \"journey\"]",
                                                                 with: "panel = [\"battery\", \"journey\", \"second\"]") }
                try ctx.wait("the new widget in the open panel", timeout: 6) { ctx.notchTexts().contains { $0.contains("second-ok") } }
                try ctx.notchURL("close")
            },
        ])
    }
}

extension Ctx {
    var icebergFolder: URL { home.appendingPathComponent(".config/grand-line/iceberg") }

    /// Writes a file in the widgets folder. In place keeps the same file (as
    /// nano or `echo >` do); otherwise it is replaced (as most editors do).
    func writeWidgetFile(_ name: String, _ text: String, inPlace: Bool = false) throws {
        let url = icebergFolder.appendingPathComponent("widgets/\(name)")
        try write(url, text, inPlace: inPlace)
    }

    /// Writes a file in the fixture home.
    func writeHomeFile(_ name: String, _ text: String) throws {
        try text.write(to: home.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// Changes iceberg.toml in place.
    func editSettings(_ change: (String) -> String) throws {
        let url = icebergFolder.appendingPathComponent("iceberg.toml")
        let before = try String(contentsOf: url, encoding: .utf8)
        let after = change(before)
        try check(after != before, "the change to iceberg.toml did not apply; it reads:\n\(before)")
        try write(url, after, inPlace: true)
    }

    private func write(_ url: URL, _ text: String, inPlace: Bool) throws {
        if inPlace, FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Runs the package's `iceberg` command (bin/iceberg) from this checkout.
    func icebergCommand(_ args: [String]) throws {
        guard let fixture = options.fixtureScript else { throw StepFailure("no --fixture-script, so bin/iceberg cannot be found") }
        let repo = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("bin/iceberg")
        guard FileManager.default.fileExists(atPath: script.path) else { throw StepFailure("\(script.path) is missing") }
        let result = Shell.run("/bin/bash", [script.path] + args, timeout: 20)
        try check(result.status == 0, "iceberg \(args.joined(separator: " ")) failed (\(result.status)): \(result.output)")
    }

    func notchURL(_ command: String) throws {
        guard let scheme = app.urlScheme else { throw StepFailure("apps.tsv names no URL scheme for \(app.name)") }
        try openApp(["\(scheme)://\(command)"], background: true)
        Input.pause(0.4)
    }

    /// The panel's window in window-server terms (top-left origin).
    func notchFrame() -> CGRect? {
        Capture.windows(pid: pid).filter { $0.bounds.minY < 60 }.max { $0.bounds.height < $1.bounds.height }?.bounds
    }

    func notchWindowID() -> CGWindowID? {
        Capture.windows(pid: pid).filter { $0.bounds.minY < 60 }.max { $0.bounds.height < $1.bounds.height }?.id
    }

    func isNotchOpen() -> Bool {
        guard let frame = notchFrame() else { return false }
        return frame.height > (closedFrame?.height ?? 40) + 40
    }

    func notchWindow() -> Element? {
        guard let frame = notchFrame() else { return nil }
        return windows().min { a, b in
            func d(_ e: Element) -> CGFloat {
                guard let f = e.frame else { return .greatestFiniteMagnitude }
                return abs(f.minX - frame.minX) + abs(f.minY - frame.minY) + abs(f.height - frame.height)
            }
            return d(a) < d(b)
        }
    }

    func notchTexts() -> [String] {
        windows().flatMap { snapshot($0).texts }
    }
}
