import AppKit
import ApplicationServices

struct StepFailure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// A step that cannot run here (no Google Drive, no settings window yet). It
/// is reported, and the journey goes on.
struct StepSkip: Error {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

final class Step {
    let name: String
    let timeout: TimeInterval?
    let checksLayout: Bool
    let body: (Ctx) throws -> Void

    init(_ name: String, timeout: TimeInterval?, checksLayout: Bool, body: @escaping (Ctx) throws -> Void) {
        self.name = name
        self.timeout = timeout
        self.checksLayout = checksLayout
        self.body = body
    }
}

func step(_ name: String, timeout: TimeInterval? = nil, layout: Bool = true, _ body: @escaping (Ctx) throws -> Void) -> Step {
    Step(name, timeout: timeout, checksLayout: layout, body: body)
}

/// A named use of one app, start to finish, as a person would go through it.
final class Journey {
    let name: String
    let role: String
    let summary: String
    let steps: [Step]
    /// The window each step's layout check and screenshot look at.
    let window: (Ctx) -> Element?
    /// Checks particular to the app, on top of the generic ones.
    let rules: (Ctx, Snapshot, CGRect) -> [String]
    /// Whether the app opens a window by itself at launch.
    let waitsForWindow: Bool
    /// Whether the app runs with the fixture as its home folder. Off only for
    /// journeys about the Mac's own settings.
    let usesFixtureHome: Bool
    /// Runs after the app quits, whether the steps passed or not (stopping a
    /// helper a step started).
    let cleanup: ((Ctx) -> Void)?

    init(_ name: String, role: String, summary: String, waitsForWindow: Bool = true, usesFixtureHome: Bool = true,
         window: @escaping (Ctx) -> Element?, rules: @escaping (Ctx, Snapshot, CGRect) -> [String] = { _, _, _ in [] },
         cleanup: ((Ctx) -> Void)? = nil, steps: [Step]) {
        self.name = name
        self.role = role
        self.summary = summary
        self.waitsForWindow = waitsForWindow
        self.usesFixtureHome = usesFixtureHome
        self.cleanup = cleanup
        self.window = window
        self.rules = rules
        self.steps = steps
    }
}

/// What a journey's steps work with: the running app, its fixture home, the
/// output folder, and helpers to act and wait.
final class Ctx {
    let app: AppEntry
    let bundle: URL
    let home: URL
    let dir: URL
    let options: Options
    var pid: pid_t = 0
    var deadline = Date.distantFuture
    var stepNumber = 0
    var metrics: [String] = []
    var notes: [String] = []
    /// Apps a step opened (a document's app), closed when the journey ends.
    var opened: [pid_t] = []
    var lastShot: URL?
    /// The notch app's closed size, and a settings window a step found.
    var closedFrame: CGRect?
    var settingsWindow: Element?
    /// More environment for the next launch (the index service to use).
    var extraEnv: [String: String] = [:]

    init(app: AppEntry, bundle: URL, home: URL, dir: URL, options: Options) {
        self.app = app
        self.bundle = bundle
        self.home = home
        self.dir = dir
        self.options = options
    }

    var ax: Element { Element.app(pid) }
    var running: NSRunningApplication? { NSRunningApplication(processIdentifier: pid) }

    // MARK: Waiting

    func wait(_ what: String, timeout: TimeInterval = 10, poll: TimeInterval = 0.1, _ condition: () throws -> Bool) throws {
        let start = Date()
        let end = min(start.addingTimeInterval(timeout), deadline)
        var lastError: Error?
        while true {
            do {
                if try condition() { return }
            } catch let skip as StepSkip {
                throw skip
            } catch {
                lastError = error
            }
            if Date() >= end { break }
            Input.pause(poll)
        }
        let why = lastError.map { " (last check: \($0))" } ?? ""
        let waited = String(format: "%.1f", Date().timeIntervalSince(start))
        throw StepFailure("timed out after \(waited) s waiting for \(what)\(why)")
    }

    /// Milliseconds until the condition holds.
    func time(_ what: String, timeout: TimeInterval = 10, poll: TimeInterval = 0.01, _ condition: () throws -> Bool) throws -> Double {
        let start = Date()
        try wait(what, timeout: timeout, poll: poll, condition)
        return Date().timeIntervalSince(start) * 1000
    }

    func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw StepFailure(message()) }
    }

    func metric(_ name: String, _ ms: Double) {
        metrics.append("\(name) \(Int(ms.rounded())) ms")
    }

    func note(_ text: String) { notes.append(text) }

    // MARK: The app

    func launch(waitForWindow: Bool, fixtureHome: Bool = true) throws {
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        if !existing.isEmpty {
            guard options.quitRunning else {
                throw StepFailure("\(app.name) is already running. Quit it first, or pass --quit-running.")
            }
            existing.forEach { $0.terminate() }
            try wait("the running \(app.name) to quit", timeout: 10) { existing.allSatisfy(\.isTerminated) }
        }
        var env = ["GRAND_LINE_JOURNEY": "1"]
        extraEnv.forEach { env[$0.key] = $0.value }
        if fixtureHome {
            env["HOME"] = home.path
            env["CFFIXED_USER_HOME"] = home.path
        }
        var args = ["-F", "-a", bundle.path]
        for key in env.keys.sorted() { args += ["--env", "\(key)=\(env[key]!)"] }
        let opened = Shell.run("/usr/bin/open", args, timeout: 40)
        if opened.status != 0 {
            // An older `open` without --env: start the program itself.
            note("open --env failed (\(opened.output.prefix(120))); started the program directly")
            let process = Process()
            process.executableURL = bundle.appendingPathComponent("Contents/MacOS/\(app.product)")
            var environment = ProcessInfo.processInfo.environment
            env.forEach { environment[$0.key] = $0.value }
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }
        try wait("\(app.name) to start", timeout: 30) {
            guard let found = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
                .first(where: { !$0.isTerminated }) else { return false }
            pid = found.processIdentifier
            return !ax.role.isEmpty
        }
        if waitForWindow { _ = try mainWindow(timeout: 30) }
    }

    func quit() {
        for other in opened {
            if let app = NSRunningApplication(processIdentifier: other) { app.terminate() }
        }
        guard pid != 0, let app = running else { return }
        app.terminate()
        let end = Date().addingTimeInterval(6)
        while !app.isTerminated, Date() < end { Input.pause(0.1) }
        if !app.isTerminated { app.forceTerminate() }
        let hard = Date().addingTimeInterval(3)
        while !app.isTerminated, Date() < hard { Input.pause(0.1) }
        if !app.isTerminated { kill(pid, SIGKILL) }
    }

    func activate() {
        ax.set("AXFrontmost", NSNumber(value: true))
        running?.activate()
        try? wait("\(app.name) to come to the front", timeout: 3) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }
    }

    /// `open -a <bundle> [url]`: what a person (or a shortcut) does to reach a running app.
    func openApp(_ arguments: [String] = [], background: Bool = false) throws {
        let result = Shell.run("/usr/bin/open", (background ? ["-g"] : []) + ["-a", bundle.path] + arguments, timeout: 20)
        try check(result.status == 0, "open -a \(app.name) \(arguments.joined(separator: " ")) failed: \(result.output)")
    }

    func windows() -> [Element] { ax.elements("AXWindows") }

    /// The focused standard window, else the first one.
    func mainWindow(timeout: TimeInterval = 10) throws -> Element {
        var found: Element?
        try wait("a window from \(app.name)", timeout: timeout) {
            if let focused = ax.element("AXFocusedWindow"), focused.string("AXSubrole") == "AXStandardWindow" {
                found = focused
            } else {
                found = windows().first { $0.string("AXSubrole") == "AXStandardWindow" }
            }
            return found != nil
        }
        return found!
    }

    func snapshot(_ window: Element) -> Snapshot { Snapshot.capture(window) }

    // MARK: Acting

    func key(_ combo: String) throws {
        try Input.press(combo)
        Input.pause(0.15)
    }

    func type(_ text: String) {
        Input.type(text)
        Input.pause(0.1)
    }

    func click(_ node: Node, count: Int = 1) throws {
        guard let center = node.center else { throw StepFailure("\(Ctx.describe(node)) has no position on screen") }
        Input.click(center, count: count)
    }

    /// A menu bar item by its path, e.g. ["View", "Sort By", "Date Added"].
    func menu(_ path: [String]) throws {
        guard let bar = ax.element("AXMenuBar") else { throw StepFailure("\(app.name) has no menu bar") }
        var items = bar.children
        for (index, title) in path.enumerated() {
            guard let item = items.first(where: { $0.title == title }) else {
                throw StepFailure("no menu item \"\(title)\" (looking for \(path.joined(separator: " > "))); found: \(items.map(\.title).filter { !$0.isEmpty }.joined(separator: ", "))")
            }
            if index == path.count - 1 {
                try check(item.perform("AXPress"), "could not choose \(path.joined(separator: " > "))")
                Input.pause(0.2)
                return
            }
            guard let submenu = item.children.first(where: { $0.role == "AXMenu" }) else {
                throw StepFailure("\(title) has no submenu")
            }
            items = submenu.children
        }
    }

    // MARK: Screenshots

    @discardableResult
    func shot(_ label: String, window: Element?) -> URL? {
        let slug = label.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let name = String(format: "%02d-", stepNumber) + String(slug).replacingOccurrences(of: "--", with: "-").prefix(60) + ".png"
        let url = dir.appendingPathComponent(name)
        let id = window.flatMap { w in Capture.windowID(pid: pid, near: w.frame) }
        if Capture.shot(to: url, window: id) {
            lastShot = url
            return url
        }
        return nil
    }

    static func describe(_ node: Node) -> String {
        var parts = [node.role]
        if !node.identifier.isEmpty { parts.append("#" + node.identifier) }
        let text = node.text.isEmpty ? node.placeholder : node.text
        if !text.isEmpty { parts.append("\"" + String(text.prefix(40)) + "\"") }
        return parts.joined(separator: " ")
    }

    static func rect(_ r: CGRect?) -> String {
        guard let r else { return "(no frame)" }
        return "(\(Int(r.minX)), \(Int(r.minY)), \(Int(r.width))x\(Int(r.height)))"
    }
}

// MARK: Running and reporting

struct StepResult {
    enum Status: String { case passed, failed, skipped, notRun = "not run" }
    let name: String
    let status: Status
    let seconds: Double
    let message: String
    let screenshot: String
}

final class JourneyResult {
    let journey: Journey
    let appName: String
    var steps: [StepResult] = []
    var seconds: Double = 0
    var metrics: [String] = []
    var notes: [String] = []

    init(journey: Journey, appName: String) {
        self.journey = journey
        self.appName = appName
    }

    var failed: StepResult? { steps.first { $0.status == .failed } }
    var passed: Bool { failed == nil }
}

/// Stops the run if one step hangs past its limit (an app that stopped
/// answering, an event that never returned), so CI never waits for its own timeout.
final class Watchdog {
    static let shared = Watchdog()
    private let lock = NSLock()
    private var limit = Date.distantFuture
    private var label = ""
    var onFire: ((String) -> Void)?

    func arm(until: Date, _ label: String) {
        lock.lock(); limit = until; self.label = label; lock.unlock()
    }

    func start() {
        Thread.detachNewThread { [self] in
            while true {
                Thread.sleep(forTimeInterval: 1)
                lock.lock()
                let over = Date() > limit
                let what = label
                lock.unlock()
                if over {
                    onFire?(what)
                    exit(3)
                }
            }
        }
    }
}

final class Runner {
    let options: Options
    let apps: [String: AppEntry]
    var results: [JourneyResult] = []
    var current: Ctx?
    let started = Date()

    init(options: Options, apps: [String: AppEntry]) {
        self.options = options
        self.apps = apps
    }

    func run(_ journeys: [Journey]) {
        Watchdog.shared.onFire = { [self] label in
            let message = "\(label) did not finish within its time limit, so the run was stopped"
            FileHandle.standardError.write(("STOPPED: " + message + "\n").data(using: .utf8)!)
            if let ctx = current, ctx.pid != 0 { kill(ctx.pid, SIGKILL) }
            if options.github { print("::error title=journeys stopped::\(Report.escape(message))") }
            Report.write(results, options: options)
        }
        Watchdog.shared.start()
        for journey in journeys {
            guard let app = apps[journey.role] else {
                print("journeys: no app for role \(journey.role) in apps.tsv")
                continue
            }
            let result = JourneyResult(journey: journey, appName: app.name)
            results.append(result)
            if Date().timeIntervalSince(started) > options.totalTimeout {
                result.steps.append(StepResult(name: "all steps", status: .notRun, seconds: 0,
                                               message: "the run reached its total time limit", screenshot: ""))
                continue
            }
            runJourney(journey, app: app, result: result)
            Report.printJourney(result)
        }
        Watchdog.shared.arm(until: .distantFuture, "")
        Report.write(results, options: options)
    }

    private func runJourney(_ journey: Journey, app: AppEntry, result: JourneyResult) {
        let start = Date()
        let dir = options.output.appendingPathComponent(journey.name)
        let home = options.output.appendingPathComponent("homes").appendingPathComponent(journey.name).appendingPathComponent("journeyhome")
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bundle = options.appsFolder!.appendingPathComponent(app.name + ".app")
        let ctx = Ctx(app: app, bundle: bundle, home: home, dir: dir, options: options)
        current = ctx
        print("\n== \(journey.name) (\(app.name)): \(journey.summary)")

        let setup = Step("launch \(app.name) with a fixture home", timeout: 90, checksLayout: true) { ctx in
            try ctx.check(FileManager.default.fileExists(atPath: bundle.path), "no app bundle at \(bundle.path)")
            let made = Shell.run("/bin/bash", [self.options.fixtureScript!.path, home.path], timeout: 60)
            try ctx.check(made.status == 0, "the fixture script failed: \(made.output)")
            try ctx.launch(waitForWindow: journey.waitsForWindow, fixtureHome: journey.usesFixtureHome)
        }
        var stopped = false
        for (index, step) in ([setup] + journey.steps).enumerated() {
            ctx.stepNumber = index
            if stopped {
                result.steps.append(StepResult(name: step.name, status: .notRun, seconds: 0, message: "", screenshot: ""))
                continue
            }
            let limit = step.timeout ?? options.stepTimeout
            ctx.deadline = Date().addingTimeInterval(limit)
            Watchdog.shared.arm(until: ctx.deadline.addingTimeInterval(45), "\(journey.name), step \"\(step.name)\"")
            let stepStart = Date()
            var status = StepResult.Status.passed
            var message = ""
            do {
                try step.body(ctx)
                // Give the screen a moment to settle before judging it.
                Input.pause(0.25)
                ctx.deadline = Date().addingTimeInterval(15)
                if step.checksLayout, let window = journey.window(ctx) {
                    try checkLayout(journey, ctx, window)
                }
            } catch let skip as StepSkip {
                status = .skipped
                message = skip.reason
            } catch {
                status = .failed
                message = "\(error)"
                stopped = true
            }
            let window = journey.window(ctx)
            let shot = ctx.shot(step.name, window: window)
            if status == .failed, let window {
                // What was on screen, so the failure can be read without the picture.
                let seen = Snapshot.capture(window, limit: 1500).texts.prefix(25).joined(separator: " | ")
                if !seen.isEmpty { message += "\nOn screen: " + seen }
            }
            let seconds = Date().timeIntervalSince(stepStart)
            result.steps.append(StepResult(name: step.name, status: status, seconds: seconds, message: message,
                                           screenshot: shot?.lastPathComponent ?? ""))
            let mark = status == .passed ? "ok  " : (status == .skipped ? "skip" : "FAIL")
            print(String(format: "  %@ %5.1f s  %@%@", mark, seconds, step.name, message.isEmpty ? "" : "\n         " + message.replacingOccurrences(of: "\n", with: "\n         ")))
        }
        Watchdog.shared.arm(until: Date().addingTimeInterval(60), "\(journey.name), quitting \(app.name)")
        ctx.quit()
        journey.cleanup?(ctx)
        result.seconds = Date().timeIntervalSince(start)
        result.metrics = ctx.metrics
        result.notes = ctx.notes
    }

    private func checkLayout(_ journey: Journey, _ ctx: Ctx, _ window: Element) throws {
        guard let frame = window.frame else { return }
        let snapshot = Snapshot.capture(window)
        let problems = Layout.generic(snapshot, window: frame) + journey.rules(ctx, snapshot, frame)
        if !problems.isEmpty {
            throw StepFailure("layout: " + problems.prefix(6).joined(separator: "; "))
        }
    }
}
