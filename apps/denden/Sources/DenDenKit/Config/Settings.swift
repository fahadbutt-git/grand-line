import Foundation

/// Den Den's own settings, from `~/.config/grand-line/denden/denden.toml`.
/// Every key is optional; a missing or broken file gives the defaults.
public struct DenDenSettings: Equatable, Sendable {
    public enum ExternalDisplays: String, Sendable, CaseIterable {
        /// Only the built-in display shows Den Den (a pill on the main
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
    public var builtin: [String] = DenDenSettings.builtinWidgets
    /// True when the file sets `builtin`, so a file from before `panel`
    /// keeps the widgets it chose.
    public var builtinIsSet = false
    /// What the panel shows, in order: built-in sections by name and script
    /// widgets by file name. Nil when the file does not say (see `PanelLayout`).
    public var panel: [String]?
    /// Opens Den Den when you log in (macOS Login Items).
    public var launchAtLogin = true
    /// A Den Den item in the menu bar, with Settings and the panel's menu.
    public var menuBarIcon = true

    public init() {}

    public static func parse(_ text: String, fileName: String = "denden.toml") -> (DenDenSettings, [ConfigIssue]) {
        var settings = DenDenSettings()
        var issues: [ConfigIssue] = []
        func warn(_ m: String) { issues.append(ConfigIssue(file: fileName, message: m, severity: .warning)) }

        let table: [String: TOMLValue]
        do {
            table = try TOML.parse(text)
        } catch let error as TOMLError {
            return (settings, [ConfigIssue(file: fileName, line: error.line, message: error.message + "; using the defaults")])
        } catch {
            return (settings, [ConfigIssue(file: fileName, message: "unreadable; using the defaults")])
        }

        for (key, value) in table.sorted(by: { $0.key < $1.key }) {
            switch (key, value) {
            case ("external_displays", .string(let s)):
                if let v = ExternalDisplays(rawValue: s.lowercased()) { settings.externalDisplays = v }
                else { warn("external_displays must be \"none\" or \"pill\"") }
            case ("open_on", .string(let s)):
                if let v = OpenOn(rawValue: s.lowercased()) { settings.openOn = v }
                else { warn("open_on must be \"hover\" or \"click\"") }
            case ("hover_delay", _), ("close_delay", _):
                let seconds: Double?
                switch value {
                case .integer(let n): seconds = Double(n)
                case .float(let d): seconds = d
                default: seconds = nil
                }
                guard let s = seconds, s >= 0, s <= 3 else { warn("\(key) must be between 0 and 3 seconds"); continue }
                if key == "hover_delay" { settings.hoverDelay = s } else { settings.closeDelay = s }
            case ("live_activity", .bool(let b)):
                settings.liveActivity = b
            case ("launch_at_login", .bool(let b)):
                settings.launchAtLogin = b
            case ("menu_bar_icon", .bool(let b)):
                settings.menuBarIcon = b
            case ("panel", .array(let items)):
                var list: [String] = []
                for item in items {
                    guard case .string(let name) = item, !name.isEmpty else { warn("panel lists names in quotes"); continue }
                    if !list.contains(name) { list.append(name) }
                }
                settings.panel = list
            case ("builtin", .array(let items)):
                var list: [String] = []
                for item in items {
                    guard case .string(let name) = item else { warn("builtin lists widget names in quotes"); continue }
                    if builtinWidgets.contains(name) { if !list.contains(name) { list.append(name) } }
                    else { warn("\"\(name)\" is not a built-in widget (\(builtinWidgets.joined(separator: ", ")))") }
                }
                settings.builtin = list
                settings.builtinIsSet = true
            default:
                warn("unknown or mistyped setting \"\(key)\" is ignored")
            }
        }
        return (settings, issues)
    }

    public static func load(from url: URL) -> (DenDenSettings, [ConfigIssue]) {
        guard let data = FileManager.default.contents(atPath: url.path) else { return (DenDenSettings(), []) }
        guard let text = String(data: data, encoding: .utf8) else {
            return (DenDenSettings(), [ConfigIssue(file: url.lastPathComponent, message: "not UTF-8 text; using the defaults")])
        }
        return parse(text, fileName: url.lastPathComponent)
    }
}
