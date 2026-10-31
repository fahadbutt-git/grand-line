import AppKit

/// The notch app (role "notch"): the panel opens from its URL commands and on
/// hover, shows only the sections turned on, has settings if it has them, and
/// follows the theme. Without a notch (CI) it sits as a pill at the top.
enum NotchJourneys {
    static let role = "notch"

    static var all: [Journey] { [panel, settings, theme] }

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
                try ctx.wait("the Journey widget's output", timeout: 10) { ctx.notchTexts().contains("journey-ok") }
            },
            step("only the sections turned on are shown") { ctx in
                let texts = ctx.notchTexts()
                try ctx.check(texts.contains("Journey"), "the Journey widget's title is missing; shown: \(texts)")
                for off in ["Today", "Reminders"] {
                    try ctx.check(!texts.contains(off), "\"\(off)\" shows although denden.toml leaves it out; shown: \(texts)")
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
                try ctx.wait("its widgets", timeout: 10) { ctx.notchTexts().contains("journey-ok") }
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
                guard Capture.canRecordScreen else { return }
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

extension Ctx {
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
