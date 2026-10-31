import Foundation

/// Iceberg's own settings, from `~/.config/grand-line/iceberg/iceberg.toml`.
/// Every key is optional; a missing or broken file gives the defaults.
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
        var settings = IcebergSettings()

        let document: TOMLDocument
        do {
            document = try TOML.parseDocument(text)
        } catch let error as TOMLError {
            return (settings, [ConfigIssue(file: fileName, line: error.line, message: error.message + "; using the defaults",
                                           severity: .error, fix: WidgetConfig.syntaxFix(for: error))])
        } catch {
            return (settings, [ConfigIssue(file: fileName, message: "unreadable; using the defaults")])
        }

        let checked = ConfigSchema.settings.check(document.values, lines: document.lines, fileName: fileName)
        var issues = checked.issues
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
        return (settings, issues)
    }

    public static func load(from url: URL) -> (IcebergSettings, [ConfigIssue]) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return (IcebergSettings(), []) }
        guard let text = String(data: data, encoding: .utf8) else {
            return (IcebergSettings(), [ConfigIssue(file: url.lastPathComponent, message: "not UTF-8 text; using the defaults")])
        }
        return parse(text, fileName: url.lastPathComponent)
    }
}
