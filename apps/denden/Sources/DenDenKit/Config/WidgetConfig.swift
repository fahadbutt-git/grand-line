import Foundation

/// When a user widget runs its command.
public enum RefreshPolicy: Equatable, Sendable, CustomStringConvertible {
    /// Every so many seconds, while the panel is open.
    case interval(TimeInterval)
    /// Each time the panel opens.
    case onOpen

    /// No widget runs more often than this, however its file is written.
    public static let minimumInterval: TimeInterval = 5

    public var description: String {
        switch self {
        case .onOpen: return "on open"
        case .interval(let s): return "every \(Int(s)) s"
        }
    }

    /// Reads `300`, `"30s"`, `"5m"`, `"1h"`, `"1d"` or `"on open"`.
    /// Returns nil for anything else.
    public static func parse(_ value: TOMLValue) -> (RefreshPolicy, clamped: Bool)? {
        let seconds: Double
        switch value {
        case .integer(let n): seconds = Double(n)
        case .float(let d): seconds = d
        case .string(let raw):
            let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if ["on open", "on-open", "on_open", "onopen", "open"].contains(s) { return (.onOpen, false) }
            guard let parsed = parseDuration(s) else { return nil }
            seconds = parsed
        default: return nil
        }
        guard seconds.isFinite, seconds > 0 else { return nil }
        if seconds < minimumInterval { return (.interval(minimumInterval), true) }
        return (.interval(seconds), false)
    }

    /// "90", "90s", "5m", "1.5h", "2d", "1m30s" in seconds.
    public static func parseDuration(_ text: String) -> Double? {
        let s = text.replacingOccurrences(of: " ", with: "")
        if s.isEmpty { return nil }
        if let plain = Double(s) { return plain }
        var total = 0.0
        var number = ""
        var sawUnit = false
        for c in s {
            if c.isNumber || c == "." {
                number.append(c)
                continue
            }
            guard let n = Double(number) else { return nil }
            switch c {
            case "s": total += n
            case "m": total += n * 60
            case "h": total += n * 3600
            case "d": total += n * 86400
            default: return nil
            }
            number = ""
            sawUnit = true
        }
        if !number.isEmpty { return nil }
        return sawUnit ? total : nil
    }
}

/// A problem found in a config file. Errors stop that one widget from
/// loading; warnings are shown but the widget still loads.
public struct ConfigIssue: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public var file: String
    public var line: Int?
    public var message: String
    public var severity: Severity

    public init(file: String, line: Int? = nil, message: String, severity: Severity = .error) {
        self.file = file
        self.line = line
        self.message = message
        self.severity = severity
    }

    public var description: String {
        let place = line.map { "\(file), line \($0)" } ?? file
        return "\(place): \(message)"
    }
}

/// One user widget, read from `~/.config/grand-line/denden/widgets/NAME.toml` or `.json`.
public struct WidgetConfig: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String
    public var command: String
    public var refresh: RefreshPolicy
    public var click: String?
    public var timeout: TimeInterval
    public var order: Int
    public var enabled: Bool
    /// The file it came from, for messages and as the command's working folder.
    public var file: URL?

    public static let defaultIcon = "square.dashed"
    public static let defaultTimeout: TimeInterval = 10
    public static let timeoutRange: ClosedRange<TimeInterval> = 1...120

    public init(id: String, title: String, icon: String = WidgetConfig.defaultIcon, command: String,
                refresh: RefreshPolicy = .onOpen, click: String? = nil,
                timeout: TimeInterval = WidgetConfig.defaultTimeout, order: Int = 0,
                enabled: Bool = true, file: URL? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.command = command
        self.refresh = refresh
        self.click = click
        self.timeout = timeout
        self.order = order
        self.enabled = enabled
        self.file = file
    }

    static let knownKeys = ["title", "icon", "command", "refresh", "click", "timeout", "order", "enabled"]
    static let aliases = ["symbol": "icon", "sf_symbol": "icon", "on_click": "click", "click_command": "click",
                          "interval": "refresh", "update_freq": "refresh", "script": "command"]

    /// The widget's id: the file name without its extension, lower case, with
    /// spaces turned into dashes.
    public static func id(forFileName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return stem.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Parses one file's contents. Never throws: everything wrong is in the issues.
    public static func parse(_ data: Data, fileName: String, file: URL? = nil) -> (WidgetConfig?, [ConfigIssue]) {
        guard let text = String(data: data, encoding: .utf8) else {
            return (nil, [ConfigIssue(file: fileName, message: "the file is not UTF-8 text")])
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        var table: [String: TOMLValue]
        if ext == "json" {
            do {
                guard case .object(let object) = try JSONValue.parse(data) else {
                    return (nil, [ConfigIssue(file: fileName, message: "the file must hold one JSON object { ... }")])
                }
                table = [:]
                for (key, value) in object {
                    if let v = value.tomlValue { table[key] = v }
                }
            } catch {
                return (nil, [ConfigIssue(file: fileName, message: "not valid JSON (\(jsonErrorSummary(error)))")])
            }
        } else {
            do {
                table = try TOML.parse(text)
            } catch let error as TOMLError {
                return (nil, [ConfigIssue(file: fileName, line: error.line, message: error.message)])
            } catch {
                return (nil, [ConfigIssue(file: fileName, message: "\(error)")])
            }
        }
        return validate(table, fileName: fileName, file: file)
    }

    static func jsonErrorSummary(_ error: Error) -> String {
        let text = "\(error)"
        if let range = text.range(of: "debugDescription: \"") {
            let rest = text[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") { return String(rest[..<end]) }
        }
        return "unreadable"
    }

    static func validate(_ raw: [String: TOMLValue], fileName: String, file: URL?) -> (WidgetConfig?, [ConfigIssue]) {
        var issues: [ConfigIssue] = []
        func warn(_ m: String) { issues.append(ConfigIssue(file: fileName, message: m, severity: .warning)) }
        func error(_ m: String) { issues.append(ConfigIssue(file: fileName, message: m, severity: .error)) }

        var table: [String: TOMLValue] = [:]
        for key in raw.keys.sorted() {
            let value = raw[key]!
            let name = aliases[key] ?? key
            if knownKeys.contains(name) {
                if table[name] != nil { warn("\"\(key)\" repeats \"\(name)\"; the first one is used"); continue }
                table[name] = value
            } else if let guess = closest(to: key, in: knownKeys) {
                warn("unknown key \"\(key)\" (did you mean \"\(guess)\"?)")
            } else {
                warn("unknown key \"\(key)\" is ignored")
            }
        }

        func text(_ key: String) -> String? {
            guard let v = table[key] else { return nil }
            guard case .string(let s) = v else { error("\"\(key)\" must be text in quotes, not \(v.kindName)"); return nil }
            return s
        }

        let id = Self.id(forFileName: fileName)
        let command = text("command")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if table["command"] == nil { error("\"command\" is missing: the shell command whose output is shown") }
        else if command?.isEmpty == true { error("\"command\" is empty") }

        var title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            if table["title"] == nil { warn("\"title\" is missing; using \"\(id)\"") }
            title = id
        }

        var icon = text("icon")?.trimmingCharacters(in: .whitespaces) ?? defaultIcon
        if icon.isEmpty || !icon.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }) {
            warn("\"\(icon)\" is not an SF Symbol name (like \"cloud.sun\"); using \"\(defaultIcon)\"")
            icon = defaultIcon
        }

        var refresh = RefreshPolicy.onOpen
        if let v = table["refresh"] {
            if let parsed = RefreshPolicy.parse(v) {
                refresh = parsed.0
                if parsed.clamped { warn("refresh is raised to \(Int(RefreshPolicy.minimumInterval)) seconds, the shortest allowed") }
            } else {
                warn("refresh must be seconds (300), a duration (\"5m\") or \"on open\"; using \"on open\"")
            }
        }

        let clickText = text("click")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let click = (clickText?.isEmpty ?? true) ? nil : clickText

        var timeout = defaultTimeout
        if let v = table["timeout"] {
            let seconds: Double?
            switch v {
            case .integer(let n): seconds = Double(n)
            case .float(let d): seconds = d
            case .string(let s): seconds = RefreshPolicy.parseDuration(s.lowercased())
            default: seconds = nil
            }
            if let s = seconds, s.isFinite {
                timeout = min(max(s, timeoutRange.lowerBound), timeoutRange.upperBound)
                if timeout != s { warn("timeout is kept between 1 and 120 seconds; using \(Int(timeout))") }
            } else {
                warn("timeout must be a number of seconds; using \(Int(defaultTimeout))")
            }
        }

        var order = 0
        if let v = table["order"] {
            if case .integer(let n) = v { order = n } else { warn("order must be a whole number") }
        }

        var enabled = true
        if let v = table["enabled"] {
            if case .bool(let b) = v { enabled = b } else { warn("enabled must be true or false") }
        }

        if issues.contains(where: { $0.severity == .error }) { return (nil, issues) }
        let config = WidgetConfig(id: id, title: title, icon: icon, command: command ?? "", refresh: refresh,
                                  click: click, timeout: timeout, order: order, enabled: enabled, file: file)
        return (config, issues)
    }

    /// The nearest known key within two edits, for "did you mean" hints.
    static func closest(to key: String, in candidates: [String]) -> String? {
        let k = key.lowercased()
        var best: (String, Int)?
        for c in candidates {
            let d = editDistance(k, c)
            if d <= 2, d < (best?.1 ?? Int.max) { best = (c, d) }
        }
        return best?.0
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
