import Foundation
import IndexKit

/// A change to make, from `SettingsActionsProvider.begin`.
public struct SettingJob: Sendable, Equatable {
    public let resultID: String
    public let executable: String
    public let arguments: [String]
    public let timeout: TimeInterval
    /// The `toggle status` names to read again once it has run.
    public let readBack: [String]
    /// The state `toggle status` should then print, when the change says it.
    public let expectedKey: String?
    public let expectedValue: Bool?
    public let expectedVolume: Int?
    /// What to suggest when the command ran but the state did not change.
    public let permission: SettingsActions.Permission?
    /// Restart, shut down and log out may not return before the Mac goes away,
    /// so running out of time is not a failure for them.
    public let toleratesTimeout: Bool
}

public enum SettingStart: Sendable, Equatable {
    case started(SettingJob)
    /// The same row is already changing: a repeated Return is ignored.
    case busy
    /// Not a change this provider runs (opening a pane, a screenshot).
    case notManaged
}

/// The settings rows (see SettingsActions). The state is read live with
/// `toggle status` once per window opening, and again after each change;
/// nothing is assumed. The window calls `begin`, then `finish` off the main
/// thread, and redraws the rows from `instantResults` after each step.
public final class SettingsActionsProvider: InstantProvider, @unchecked Sendable {
    public static let providerID = "settings-actions"
    /// Sight's default (com.grandline.sight) that hides the window after a change.
    public static let closeAfterChangeKey = "CloseAfterSettingChange"

    public let id = SettingsActionsProvider.providerID
    public let title = "Settings"
    public let symbol = "switch.2"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true

    let paths: GrandLinePaths
    let runner: any CommandRunning
    private let lock = NSLock()
    private var state: SettingsState?
    private var reading = false
    private var generation = 0
    private var phases: [String: SettingPhase] = [:]

    /// The runner should set GRAND_LINE_QUIET, so the commands report through
    /// their exit status and this row instead of a notification as well.
    public init(paths: GrandLinePaths = GrandLinePaths(), runner: (any CommandRunning)? = nil) {
        self.paths = paths
        var environment = ShellRunner.environment(paths: paths)
        environment["GRAND_LINE_QUIET"] = "1"
        self.runner = runner ?? ShellRunner(environment: environment)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The state read since the window opened, or nil while it is being read.
    public var currentState: SettingsState? { locked { state } }

    public func phase(of resultID: String) -> SettingPhase? { locked { phases[resultID] } }

    // MARK: Reading the state

    /// The window opened: forget the last state, so nothing shown is older than
    /// this opening, and clear old failures. Changes still running keep their row.
    public func panelOpened() {
        locked {
            generation += 1
            state = nil
            reading = false
            phases = phases.filter { if case .running = $0.value { return true } else { return false } }
        }
    }

    /// Whether the caller should start `readState()` now: there is no state
    /// for this opening and no read under way.
    public func claimRead() -> Bool {
        locked {
            guard state == nil, !reading else { return false }
            reading = true
            return true
        }
    }

    /// Reads every setting, or only `names`, with `toggle status`.
    public func readState(_ names: [String] = []) async {
        let started = locked { generation }
        let output = try? await runner.run(paths.command("toggle"), ["status"] + names, timeout: 6)
        let fresh = output.flatMap { $0.status == 0 ? SettingsState.parse($0.stdout) : nil } ?? SettingsState()
        locked {
            guard generation == started else { return }
            if names.isEmpty { reading = false }
            state = names.isEmpty ? fresh : (state ?? SettingsState()).merging(fresh)
        }
    }

    // MARK: Changing

    /// Marks the row as changing and returns what to run, or why not.
    public func begin(_ action: LaunchAction, resultID: String) -> SettingStart {
        guard case .run(let executable, let arguments) = action.command,
              executable == paths.command("toggle") || executable == paths.command("power"),
              let job = job(executable: executable, arguments: arguments, resultID: resultID)
        else { return .notManaged }
        return locked {
            if case .running? = phases[resultID] { return .busy }
            phases[resultID] = .running(Self.progress(job, resultID: resultID))
            return .started(job)
        }
    }

    /// Runs the change, reads the state back and records the outcome on the
    /// row. Returns the failure, or nil when the change took.
    @discardableResult
    public func finish(_ job: SettingJob) async -> SettingFailure? {
        var failure: SettingFailure?
        do {
            let output = try await runner.run(job.executable, job.arguments, timeout: job.timeout)
            failure = Self.failure(status: output.status, output: output.stdout, job: job)
        } catch {
            failure = SettingFailure("The command could not start. Run: update")
        }
        if !job.readBack.isEmpty { await readState(job.readBack) }
        if failure == nil {
            let read = currentState
            if let key = job.expectedKey, let want = job.expectedValue, let got = read?.values[key], got != want {
                failure = SettingFailure("macOS did not make the change", permission: job.permission)
            } else if let want = job.expectedVolume, let got = read?.volume, got != want {
                failure = SettingFailure("The volume is \(got)%, not \(want)%")
            }
        }
        locked { phases[job.resultID] = failure.map { SettingPhase.failed($0) } }
        return failure
    }

    func job(executable: String, arguments: [String], resultID: String) -> SettingJob? {
        let key = resultID.hasPrefix("setting.") ? String(resultID.dropFirst("setting.".count)) : resultID
        if key.hasPrefix("volume") {
            var expected: Int?
            if arguments.count == 2, let n = Int(arguments[1]) { expected = n }
            return SettingJob(resultID: resultID, executable: executable, arguments: arguments, timeout: 8,
                              readBack: ["volume", "mute"], expectedKey: nil, expectedValue: nil, expectedVolume: expected,
                              permission: nil, toleratesTimeout: false)
        }
        guard let setting = SettingsActions.byKey[key] else { return nil }
        switch setting.kind {
        case .toggle(_, let stateKey, _):
            let value: Bool? = arguments.count == 2 ? arguments[1] == "on" : nil
            // The microphone's toggle state is "muted", so on is muted.
            return SettingJob(resultID: resultID, executable: executable, arguments: arguments, timeout: setting.timeout,
                              readBack: [stateKey], expectedKey: value == nil ? nil : stateKey, expectedValue: value, expectedVolume: nil,
                              permission: setting.permission, toleratesTimeout: false)
        case .power(let what, _):
            return SettingJob(resultID: resultID, executable: executable, arguments: arguments, timeout: setting.timeout,
                              readBack: [], expectedKey: nil, expectedValue: nil, expectedVolume: nil,
                              permission: setting.permission, toleratesTimeout: ["restart", "shutdown", "logout", "sleep"].contains(what))
        case .capture, .paneOnly:
            return nil
        }
    }

    static func progress(_ job: SettingJob, resultID: String) -> String {
        if resultID.hasPrefix("setting.volume") { return "Setting the volume…" }
        let key = String(resultID.dropFirst("setting.".count))
        guard let setting = SettingsActions.byKey[key], case .toggle(_, _, let inverted) = setting.kind else { return "Working…" }
        guard job.arguments.count == 2 else { return "Switching…" }
        let on = (job.arguments[1] == "on") != inverted
        return on ? "Turning on…" : "Turning off…"
    }

    /// The exit codes of fail() in lib/bin-common.sh, as a sentence.
    static let automationMessage = "Allow Automation for System Events in Privacy & Security"

    static func failure(status: Int32, output: String, job: SettingJob) -> SettingFailure? {
        let said = output.split(separator: "\n").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        // osascript's own words when Apple events are refused (-1743), from a
        // command that did not turn them into exit status 3.
        if status != 0, output.contains("-1743") || output.contains("Not authorized to send Apple events") {
            return SettingFailure(automationMessage, permission: .automation)
        }
        switch status {
        case 0: return nil
        case 3: return SettingFailure(said.isEmpty ? automationMessage : said, permission: .automation)
        case 5: return SettingFailure(said.isEmpty ? "Allow Accessibility in Privacy & Security" : said, permission: .accessibility)
        case 4: return SettingFailure(said.isEmpty ? "A tool it needs is not installed. Run: update" : said)
        case 2: return SettingFailure("This version of toggle does not know that setting. Run: update")
        case 15:
            if job.toleratesTimeout { return nil }
            // A change made through System Events that never answers is
            // waiting on the Automation question macOS asks (or cannot ask).
            if job.permission == .automation {
                return SettingFailure("System Events did not answer. " + automationMessage, permission: .automation)
            }
            return SettingFailure("It took too long and was stopped")
        default: return SettingFailure(said.isEmpty ? "It failed (status \(status))" : said)
        }
    }

    // MARK: Rows

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard query.prefix == nil, !query.isPath, !query.term.isEmpty else { return [] }
        let matches = SettingsActions.parse(query.term)
        guard !matches.isEmpty else { return [] }
        let (state, phases) = locked { (self.state, self.phases) }
        return matches.compactMap { Self.row($0, state: state, phases: phases, paths: paths) }
    }

    static func paneAction(_ setting: SettingsActions.Setting?, title: String? = nil) -> LaunchAction? {
        guard let name = setting?.pane, let pane = SettingsPanes.all.first(where: { $0.title == name }) else { return nil }
        return LaunchAction(title ?? "Open \(name) settings", symbol: "gear", .openURL(pane.url, bundleID: nil))
    }

    static let soundPane = SettingsActions.byKey["mute"]

    public static func row(_ match: SettingsActions.Match, state: SettingsState?, phases: [String: SettingPhase], paths: GrandLinePaths) -> LaunchResult? {
        let id = SettingsActions.rowID(match.request)
        var title: String
        var subtitle = ""
        var accessory = ""
        var symbol: String
        var primary: LaunchAction
        var setting: SettingsActions.Setting?
        var name = ""
        let toggle = paths.command("toggle")

        switch match.request {
        case .toggle(let key, let desired):
            guard let found = SettingsActions.byKey[key], case .toggle(let toggleName, _, let inverted) = found.kind else { return nil }
            setting = found
            name = found.title
            symbol = found.symbol
            let current = state?.shown(found)
            // Return asks for the state typed, unless it is already so; then
            // it offers the other one, so a second Return undoes the first.
            var target = desired
            if let current { target = (desired != nil && desired != current) ? desired : !current }
            let arguments = target.map { [toggleName, ($0 != inverted) ? "on" : "off"] } ?? [toggleName]
            primary = LaunchAction(target.map { $0 ? "Turn on" : "Turn off" } ?? "Switch", symbol: "switch.2", closesWindow: false, .run(toggle, arguments: arguments))
            if let current {
                title = "\(found.title): \(current ? "On" : "Off")"
                accessory = current ? "On" : "Off"
            } else {
                title = found.title
            }
            if let target {
                subtitle = target ? "Return turns it on" : "Return turns it off"
            } else {
                subtitle = state == nil ? "Checking…" : "Return switches it"
            }
        case .volumeSet(let level):
            setting = soundPane
            name = "Volume"
            symbol = "speaker.wave.2"
            title = "Set volume to \(level)%"
            primary = LaunchAction("Set volume", symbol: "speaker.wave.2", closesWindow: false, .run(toggle, arguments: ["volume", String(level)]))
            subtitle = volumeNote(state, after: { _ in level })
            accessory = state?.volume.map { "\($0)%" } ?? ""
        case .volumeUp, .volumeDown:
            let up = match.request == .volumeUp
            setting = soundPane
            name = "Volume"
            symbol = up ? "speaker.plus" : "speaker.minus"
            title = up ? "Volume up" : "Volume down"
            primary = LaunchAction(title, symbol: symbol, closesWindow: false, .run(toggle, arguments: ["volume", up ? "up" : "down"]))
            subtitle = volumeNote(state, after: { min(100, max(0, $0 + (up ? 10 : -10))) })
            accessory = state?.volume.map { "\($0)%" } ?? ""
        case .action(let key):
            guard let found = SettingsActions.byKey[key] else { return nil }
            setting = found
            name = found.title
            symbol = found.symbol
            title = found.title
            switch found.kind {
            case .power(let what, let confirm):
                primary = LaunchAction(found.title, symbol: found.symbol, confirmation: confirm, .run(paths.command("power"), arguments: [what]))
                subtitle = confirm == nil ? "Return does it now" : "Asks first"
            case .capture(let what):
                primary = LaunchAction(found.title, symbol: found.symbol, .run(paths.command("capture"), arguments: [what]))
                subtitle = "Capture"
            case .paneOnly(let reason):
                guard let open = paneAction(found) else { return nil }
                primary = open
                subtitle = reason
            case .toggle:
                return nil
            }
        }

        var actions = [primary]
        switch phases[id] {
        case .running(let text)?:
            title = name + ": " + text
            subtitle = ""
            accessory = "Working"
        case .failed(let failure)?:
            title = name + ": not changed"
            subtitle = failure.message
            accessory = "Failed"
            var retry = primary
            retry.title = "Try again"
            if let permission = failure.permission {
                actions = [LaunchAction("Open \(permission.title) settings", symbol: "hand.raised", .openURL(permission.paneURL, bundleID: nil)), retry]
            } else {
                actions = [retry]
            }
        case nil:
            break
        }
        if case .paneOnly? = setting?.kind {} else if let pane = paneAction(setting) {
            actions.append(pane)
        }

        return LaunchResult(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: .symbol(symbol),
            section: .system,
            accessory: accessory,
            actions: actions,
            providerID: providerID,
            match: match.exact
                ? MatchInfo(alias: .exact, title: .exact, quality: match.order)
                : MatchInfo(title: .prefix, quality: match.order)
        )
    }

    static func volumeNote(_ state: SettingsState?, after: (Int) -> Int) -> String {
        guard let state else { return "Checking…" }
        guard let now = state.volume else { return "This output has no volume control" }
        let next = after(now)
        return next == now ? "Now \(now)%" : "Now \(now)%, Return makes it \(next)%"
    }
}
