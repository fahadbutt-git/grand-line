import Foundation

/// Iceberg's own settings, from `~/.config/grand-line/iceberg/iceberg.toml`.
/// Every key is optional; a missing file gives the defaults. On a reload
/// (`reload(from:previous:)`) a broken file keeps the last good settings.
public struct IcebergSettings: Equatable, Sendable {
    public enum ExternalDisplays: String, Sendable, CaseIterable {
        /// Only the built-in display shows Iceberg (a pill on the main
        /// display when the lid is closed).
        case none
        /// Every display without a notch also gets a pill at the top centre.
        case pill
    }

    public enum OpenOn: String, Sendable, CaseIterable { case hover, click }

    /// The built-in widgets, in panel order.
    public static let builtinWidgets = ["now-playing", "today", "reminders", "battery"]

    public var externalDisplays: ExternalDisplays = .none
    public var openOn: OpenOn = .hover
    /// Seconds the pointer rests on the notch before it opens.
    public var hoverDelay: TimeInterval = 0.12
    /// Seconds after the pointer leaves before it closes.
    public var closeDelay: TimeInterval = 0.35
    /// Artwork and a playing mark beside the closed notch while music plays.
    public var liveActivity = true
    /// The older way to choose built-in widgets; `panel` replaces it.
    public var builtin: [String] = IcebergSettings.builtinWidgets
    /// True when the file sets `builtin`, so a file from before `panel`
    /// keeps the widgets it chose.
    public var builtinIsSet = false
    /// What the panel shows, in order: built-in sections by name and script
    /// widgets by file name. Nil when the file does not say (see `PanelLayout`).
    public var panel: [String]?
    /// Opens Iceberg when you log in (macOS Login Items).
    public var launchAtLogin = true
    /// An Iceberg item in the menu bar, with Settings and the panel's menu.
    public var menuBarIcon = true
    /// Opens or closes the panel from any app; nil when turned off.
    public var toggleShortcut: KeyShortcut? = .defaultToggle
    /// The most widget commands that run at once (and the most streams).
    public var maxConcurrent = 4

    public init() {}

    public static func parse(_ text: String, fileName: String = "iceberg.toml") -> (IcebergSettings, [ConfigIssue]) {
        let p = parseDetailed(text, fileName: fileName, fallback: "using the defaults")
        return (p.settings, p.issues)
    }

    /// One read of the file: the settings, its problems, whether it could be
    /// read at all, and the keys it set to a value that was turned down.
    struct Parsed {
        var settings: IcebergSettings
        var issues: [ConfigIssue]
        var readable: Bool
        var rejected: Set<String>
    }

    static func parseDetailed(_ text: String, fileName: String, fallback: String) -> Parsed {
        var settings = IcebergSettings()

        let document: TOMLDocument
        do {
            document = try TOML.parseDocument(text)
        } catch let error as TOMLError {
            return Parsed(settings: settings,
                          issues: [ConfigIssue(file: fileName, line: error.line, message: error.message + "; " + fallback,
                                               severity: .error, fix: WidgetConfig.syntaxFix(for: error))],
                          readable: false, rejected: [])
        } catch {
            return Parsed(settings: settings, issues: [ConfigIssue(file: fileName, message: "unreadable; " + fallback)],
                          readable: false, rejected: [])
        }

        let checked = ConfigSchema.settings.check(document.values, lines: document.lines, fileName: fileName)
        var issues = checked.issues
        var rejected: Set<String> = []
        for rawKey in document.values.keys {
            if let spec = ConfigSchema.settings.key(named: rawKey), checked.values[spec.name] == nil { rejected.insert(spec.name) }
        }
        func warn(_ key: String, _ m: String, fix: String) {
            issues.append(ConfigIssue(file: fileName, line: checked.lines[key], message: m, severity: .warning, fix: fix))
        }
        func number(_ v: TOMLValue) -> Double? {
            switch v {
            case .integer(let n): return Double(n)
            case .float(let d): return d
            default: return nil
            }
        }

        for (key, value) in checked.values.sorted(by: { $0.key < $1.key }) {
            switch (key, value) {
            case ("external_displays", .string(let s)):
                settings.externalDisplays = ExternalDisplays(rawValue: s) ?? .none
            case ("open_on", .string(let s)):
                settings.openOn = OpenOn(rawValue: s) ?? .hover
            case ("hover_delay", _):
                settings.hoverDelay = number(value) ?? settings.hoverDelay
            case ("close_delay", _):
                settings.closeDelay = number(value) ?? settings.closeDelay
            case ("live_activity", .bool(let b)):
                settings.liveActivity = b
            case ("launch_at_login", .bool(let b)):
                settings.launchAtLogin = b
            case ("menu_bar_icon", .bool(let b)):
                settings.menuBarIcon = b
            case ("toggle_shortcut", .string(let s)):
                settings.toggleShortcut = s.isEmpty ? nil : KeyShortcut.parse(s)
            case ("max_concurrent", .integer(let n)):
                settings.maxConcurrent = n
            case ("panel", .array(let items)):
                var list: [String] = []
                for item in items {
                    guard case .string(let name) = item, !name.isEmpty else {
                        warn(key, "panel lists names in quotes", fix: "Write each name in double quotes, like panel = [\"date\", \"today\"].")
                        continue
                    }
                    if !list.contains(name) { list.append(name) }
                }
                settings.panel = list
            case ("builtin", .array(let items)):
                var list: [String] = []
                for item in items {
                    guard case .string(let name) = item else {
                        warn(key, "builtin lists widget names in quotes", fix: "Write each name in double quotes.")
                        continue
                    }
                    if builtinWidgets.contains(name) { if !list.contains(name) { list.append(name) } }
                    else {
                        warn(key, "\"\(name)\" is not a built-in widget (\(builtinWidgets.joined(separator: ", ")))",
                             fix: "Remove \"\(name)\", or use panel = [...], which also takes widget file names.")
                    }
                }
                settings.builtin = list
                settings.builtinIsSet = true
            default:
                break
            }
        }
        return Parsed(settings: settings, issues: issues, readable: true, rejected: rejected)
    }

    public static func load(from url: URL) -> (IcebergSettings, [ConfigIssue]) {
        let r = reload(from: url, previous: nil)
        return (r.settings, r.issues)
    }

    /// iceberg.toml is a few lines; a larger file is refused.
    public static let maxFileSize = 256 * 1024

    /// What a reload of iceberg.toml gives.
    public struct Reload: Equatable, Sendable {
        public var settings: IcebergSettings
        public var issues: [ConfigIssue]
        /// True when the file could not be used and `previous` was kept whole.
        public var keptPrevious: Bool
        /// False when the file could not be used (whether or not there were
        /// settings to keep): nothing outside the app should follow it then.
        public var fileUsable: Bool

        public init(settings: IcebergSettings, issues: [ConfigIssue], keptPrevious: Bool, fileUsable: Bool? = nil) {
            self.settings = settings
            self.issues = issues
            self.keptPrevious = keptPrevious
            self.fileUsable = fileUsable ?? !keptPrevious
        }
    }

    /// Reads iceberg.toml again after a save. With `previous` (the settings
    /// in use), a file that cannot be used keeps them: a syntax error, text
    /// that is not UTF-8, or a file that is missing or empty for a moment (an
    /// editor that truncates or renames as it saves). A key whose new value
    /// is turned down keeps its previous value, not the default. Without
    /// `previous` (the first read) the defaults stand in, as before.
    public static func reload(from url: URL, previous: IcebergSettings?) -> Reload {
        let name = url.lastPathComponent
        let fallback = previous == nil ? "using the defaults" : "keeping the last good settings"
        let data: Data
        switch SafeFileRead.read(url, limit: maxFileSize) {
        case .success(let d):
            data = d
        case .failure(.missing):
            if let previous { return Reload(settings: previous, issues: [], keptPrevious: true) }
            return Reload(settings: IcebergSettings(), issues: [], keptPrevious: false)
        case .failure(let why):
            let what: String
            switch why {
            case .tooLarge: what = "larger than \(maxFileSize / 1024) KB"
            case .notAFile: what = "not a regular file"
            default: what = "unreadable"
            }
            return Reload(settings: previous ?? IcebergSettings(), issues: [ConfigIssue(file: name, message: what + "; " + fallback)],
                          keptPrevious: previous != nil, fileUsable: false)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return Reload(settings: previous ?? IcebergSettings(),
                          issues: [ConfigIssue(file: name, message: "not UTF-8 text; " + fallback)],
                          keptPrevious: previous != nil, fileUsable: false)
        }
        if let previous, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Reload(settings: previous, issues: [], keptPrevious: true)
        }
        let p = parseDetailed(text, fileName: name, fallback: fallback)
        guard p.readable else {
            return Reload(settings: previous ?? p.settings, issues: p.issues, keptPrevious: previous != nil, fileUsable: false)
        }
        var settings = p.settings
        if let previous {
            for key in p.rejected { settings.take(key, from: previous) }
        }
        return Reload(settings: settings, issues: p.issues, keptPrevious: false)
    }

    /// Copies one key's value from `other` (by its iceberg.toml name).
    mutating func take(_ key: String, from other: IcebergSettings) {
        switch key {
        case "external_displays": externalDisplays = other.externalDisplays
        case "open_on": openOn = other.openOn
        case "hover_delay": hoverDelay = other.hoverDelay
        case "close_delay": closeDelay = other.closeDelay
        case "live_activity": liveActivity = other.liveActivity
        case "launch_at_login": launchAtLogin = other.launchAtLogin
        case "menu_bar_icon": menuBarIcon = other.menuBarIcon
        case "toggle_shortcut": toggleShortcut = other.toggleShortcut
        case "max_concurrent": maxConcurrent = other.maxConcurrent
        case "panel": panel = other.panel
        case "builtin":
            builtin = other.builtin
            builtinIsSet = other.builtinIsSet
        default: break
        }
    }
}

/// Whether to touch macOS Login Items after reading iceberg.toml: on the
/// first good read (to match the file), and later only when the setting
/// itself changed. Never for a file that could not be used.
public enum LoginItemPolicy {
    public static func shouldApply(wanted: Bool, applied: Bool?, fileUsable: Bool) -> Bool {
        guard fileUsable else { return false }
        guard let applied else { return true }
        return applied != wanted
    }
}
