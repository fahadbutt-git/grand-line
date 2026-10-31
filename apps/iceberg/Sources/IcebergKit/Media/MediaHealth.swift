import Foundation

/// What a run of the adapter's `test` command says.
public enum AdapterCheck: Equatable, Sendable {
    /// It read Now Playing.
    case healthy
    /// It loaded, but nothing was playing so it could not tell (its full
    /// test needs a helper Iceberg does not ship).
    case inconclusive
    /// It could not load or read MediaRemote.
    case broken(String)

    /// Reads `perl mediaremote-adapter.pl FRAMEWORK test`'s result.
    public static func evaluate(exitCode: Int32?, stderr: String, timedOut: Bool, launchError: String?) -> AdapterCheck {
        if let launchError { return .broken(launchError) }
        if timedOut { return .broken("the check did not answer") }
        if exitCode == 0 { return .healthy }
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        // Without the test client the adapter can only test while something
        // plays; this message means the framework loaded and ran.
        if text.contains("Test client path is missing") { return .inconclusive }
        let firstLine = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        if firstLine.isEmpty { return .broken("the check ended with status \(exitCode.map { String($0) } ?? "unknown")") }
        return .broken(CommandOutputParser.clean(firstLine))
    }
}

/// Whether the AppleScript fallback can ask Music and Spotify.
public enum AppleScriptStatus: Equatable, Sendable {
    /// Not needed yet.
    case unused
    case working
    /// macOS turned it down (Automation permission).
    case denied
    case failed(String)

    /// From an NSAppleScript error number (nil: it ran).
    public static func from(errorNumber: Int?, message: String?) -> AppleScriptStatus {
        guard let n = errorNumber else { return .working }
        switch n {
        case -1743, -1744: return .denied
        // The player quit between the check and the call: not a fault.
        case -600, -609, -1728: return .working
        default: return .failed(message ?? "error \(n)")
        }
    }
}

/// Where Now Playing comes from.
public enum MediaSource: Equatable, Sendable {
    /// mediaremote-adapter: every player macOS knows about, with artwork.
    case adapter
    /// Music and Spotify, asked with AppleScript and their own change notices.
    case appleScript
    /// Neither works.
    case none
}

/// The Now Playing source's health: the adapter, checked at launch and
/// every few minutes, and the AppleScript fallback for when it fails.
public struct MediaHealth: Equatable, Sendable {
    /// How often the adapter is checked again while Now Playing is on.
    public static let checkInterval: TimeInterval = 5 * 60

    /// False when the adapter is not in the app at all.
    public var adapterBundled: Bool
    /// The last check's result, nil before the first.
    public var lastCheck: AdapterCheck?
    public var lastCheckAt: Date?
    /// The adapter's stream kept exiting.
    public var streamGaveUp = false
    public var appleScript: AppleScriptStatus = .unused

    public init(adapterBundled: Bool) {
        self.adapterBundled = adapterBundled
    }

    /// True while the adapter should be used.
    public var adapterUsable: Bool {
        guard adapterBundled, !streamGaveUp else { return false }
        if case .broken? = lastCheck { return false }
        return true
    }

    public var source: MediaSource {
        if adapterUsable { return .adapter }
        switch appleScript {
        case .denied, .failed: return .none
        case .unused, .working: return .appleScript
        }
    }

    /// Why the adapter is not used, in a few words.
    public var adapterProblem: String? {
        if !adapterBundled { return "the Now Playing helper is not in this copy of Iceberg" }
        if streamGaveUp { return "the Now Playing helper keeps stopping" }
        if case .broken(let why)? = lastCheck { return "the Now Playing helper failed its check (\(why))" }
        return nil
    }

    /// One line for Settings.
    public var summary: String {
        switch source {
        case .adapter:
            return "Working: every player macOS knows about, with artwork."
        case .appleScript:
            return "Music and Spotify only, without artwork: \(adapterProblem ?? "the Now Playing helper is not working")."
        case .none:
            let script: String
            switch appleScript {
            case .denied: script = "macOS does not allow Iceberg to ask Music and Spotify"
            case .failed(let why): script = "asking Music and Spotify failed (\(why))"
            default: script = "Music and Spotify cannot be asked"
            }
            return "Not working: \(adapterProblem ?? "the Now Playing helper failed"), and \(script)."
        }
    }

    /// What to do about it, when anything can be done.
    public var fix: String? {
        switch source {
        case .adapter:
            return nil
        case .appleScript:
            return adapterBundled
                ? "Other players show again when the helper works; Iceberg checks every few minutes, or click Check again. A macOS update can stop it until Iceberg is updated."
                : "Rebuild Iceberg with setup (or bash build.sh) to include the helper."
        case .none:
            if appleScript == .denied {
                return "Allow Iceberg for Music and Spotify in System Settings › Privacy & Security › Automation, then click Check again."
            }
            return "Click Check again. If it stays broken, see the log for the reason."
        }
    }

    /// Notes a check. A healthy check also clears an earlier give-up, so the
    /// adapter is tried again.
    public mutating func record(_ check: AdapterCheck, at now: Date) {
        lastCheck = check
        lastCheckAt = now
        if check == .healthy { streamGaveUp = false }
    }

    /// True when a check is due.
    public func checkDue(at now: Date) -> Bool {
        guard adapterBundled else { return false }
        guard let at = lastCheckAt else { return true }
        return now.timeIntervalSince(at) >= Self.checkInterval - 1
    }
}

/// The AppleScript fallback: asks Music or Spotify what is playing. Each
/// script first checks the app is running, so asking never opens it.
public enum AppleScriptNowPlaying {
    public struct Player: Equatable, Sendable {
        public var name: String
        public var bundleIdentifier: String
        /// Spotify reports durations in milliseconds, Music in seconds.
        public var durationInMilliseconds: Bool
    }

    public static let spotify = Player(name: "Spotify", bundleIdentifier: "com.spotify.client", durationInMilliseconds: true)
    public static let music = Player(name: "Music", bundleIdentifier: "com.apple.Music", durationInMilliseconds: false)
    public static let players = [spotify, music]

    /// Prints "state<TAB>title<TAB>artist<TAB>album<TAB>duration<TAB>position",
    /// "stopped", or "" when the app is not running.
    public static func script(for player: Player) -> String {
        """
        if application "\(player.name)" is running then
            tell application "\(player.name)"
                if player state is stopped then return "stopped"
                set t to current track
                set out to (player state as text) & tab & (name of t as text) & tab & (artist of t as text)
                set out to out & tab & (album of t as text) & tab & (duration of t as text) & tab & (player position as text)
                return out
            end tell
        end if
        return ""
        """
    }

    /// The script's answer as a Now Playing payload: nil when the app is
    /// not running, empty when it is stopped.
    public static func payload(from output: String, player: Player, now: Date = Date()) -> [String: JSONValue]? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text == "stopped" { return [:] }
        let fields = text.components(separatedBy: "\t")
        guard fields.count >= 2 else { return nil }
        let state = fields[0].lowercased()
        if state.contains("stopped") { return [:] }
        var p: [String: JSONValue] = [
            "bundleIdentifier": .string(player.bundleIdentifier),
            "playing": .bool(state.contains("playing")),
        ]
        func field(_ i: Int) -> String? {
            guard i < fields.count else { return nil }
            let s = fields[i].trimmingCharacters(in: .whitespaces)
            return s.isEmpty || s == "missing value" ? nil : s
        }
        // Numbers come in the Mac's own format ("215,4" in many regions).
        func number(_ i: Int) -> Double? {
            field(i).flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
        }
        if let s = field(1) { p["title"] = .string(s) }
        if let s = field(2) { p["artist"] = .string(s) }
        if let s = field(3) { p["album"] = .string(s) }
        if let d = number(4), d > 0 { p["duration"] = .number(player.durationInMilliseconds ? d / 1000 : d) }
        if let pos = number(5), pos >= 0 {
            p["elapsedTime"] = .number(pos)
            p["timestamp"] = .number(now.timeIntervalSince1970)
        }
        return p
    }
}
