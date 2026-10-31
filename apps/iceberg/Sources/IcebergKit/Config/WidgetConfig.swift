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
    /// What to change, in plain words, for the Problems list.
    public var fix: String?

    public init(file: String, line: Int? = nil, message: String, severity: Severity = .error, fix: String? = nil) {
        self.file = file
        self.line = line
        self.message = message
        self.severity = severity
        self.fix = fix
    }

    public var description: String {
        let place = line.map { "\(file), line \($0)" } ?? file
        return "\(place): \(message)"
    }

    /// `file:line`, as editors and the Problems list show it.
    public var location: String {
        line.map { "\(file):\($0)" } ?? file
    }
}

/// When a widget's command may run.
public enum WidgetUpdates: String, Equatable, Sendable {
    /// Only while the panel is open, plus one refresh as it opens (the default).
    case whenShown = "when_shown"
    /// Also while the panel is closed, so the value is current when it opens.
    case always
}

/// How a widget gets its output.
public enum WidgetMode: Equatable, Sendable, CustomStringConvertible {
    /// Runs on its `refresh` schedule and shows the output.
    case poll(RefreshPolicy)
    /// Runs when `iceberg trigger NAME` is called, and as the panel opens
    /// (or on its `refresh` schedule when one is set).
    case signal(RefreshPolicy)
    /// Keeps running; every line it prints is an update.
    case stream

    public var description: String {
        switch self {
        case .poll(let p): return "runs \(p.description)"
        case .signal(.onOpen): return "runs on a signal and on open"
        case .signal(let p): return "runs on a signal and \(p.description)"
        case .stream: return "streams"
        }
    }
}

/// One user widget, read from `~/.config/grand-line/iceberg/widgets/NAME.toml` or `.json`.
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
    /// Runs when `iceberg trigger NAME` (or `iceberg://trigger/NAME`) asks.
    public var signal: Bool
    /// A long-running command that prints one line (often JSON) per update.
    public var stream: Bool
    public var updates: WidgetUpdates
    /// Runs during Low Power Mode and around sleep too.
    public var always: Bool
    /// The file it came from, for messages and as the command's working folder.
    public var file: URL?

    public static let defaultIcon = "square.dashed"
    public static let defaultTimeout: TimeInterval = 10
    public static let timeoutRange: ClosedRange<TimeInterval> = 1...120

    public init(id: String, title: String, icon: String = WidgetConfig.defaultIcon, command: String,
                refresh: RefreshPolicy = .onOpen, click: String? = nil,
                timeout: TimeInterval = WidgetConfig.defaultTimeout, order: Int = 0,
                enabled: Bool = true, signal: Bool = false, stream: Bool = false,
                updates: WidgetUpdates = .whenShown, always: Bool = false, file: URL? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.command = command
        self.refresh = refresh
        self.click = click
        self.timeout = timeout
        self.order = order
        self.enabled = enabled
        self.signal = signal
        self.stream = stream
        self.updates = updates
        self.always = always
        self.file = file
    }

    public var mode: WidgetMode {
        if stream { return .stream }
        return signal ? .signal(refresh) : .poll(refresh)
    }

    /// True when it may run while the panel is closed.
    public var runsWhileClosed: Bool { updates == .always }

    /// The widget's id: the file name without its extension, lower case, with
    /// spaces turned into dashes.
    public static func id(forFileName name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return stem.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    /// Parses one file's contents. Never throws: everything wrong is in the issues.
    public static func parse(_ data: Data, fileName: String, file: URL? = nil) -> (WidgetConfig?, [ConfigIssue]) {
        guard let text = String(data: data, encoding: .utf8) else {
            return (nil, [ConfigIssue(file: fileName, message: "the file is not UTF-8 text",
                                      fix: "Save the file as UTF-8 text (any plain-text editor does).")])
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        var table: [String: TOMLValue]
        var lines: [String: Int] = [:]
        if ext == "json" {
            do {
                guard case .object(let object) = try JSONValue.parse(data) else {
                    return (nil, [ConfigIssue(file: fileName, message: "the file must hold one JSON object { ... }",
                                              fix: "Put the keys inside one pair of braces: { \"command\": \"date\" }")])
                }
                table = [:]
                for (key, value) in object {
                    if let v = value.tomlValue { table[key] = v }
                }
                lines = JSONKeyLines.lines(in: text)
            } catch {
                return (nil, [ConfigIssue(file: fileName, message: "not valid JSON (\(jsonErrorSummary(error)))",
                                          fix: "Check the quotes, commas and braces; a JSON checker names the exact spot.")])
            }
        } else {
            do {
                let document = try TOML.parseDocument(text)
                table = document.values
                lines = document.lines
            } catch let error as TOMLError {
                return (nil, [ConfigIssue(file: fileName, line: error.line, message: error.message,
                                          fix: syntaxFix(for: error))])
            } catch {
                return (nil, [ConfigIssue(file: fileName, message: "\(error)")])
            }
        }
        return validate(table, lines: lines, fileName: fileName, file: file)
    }

    /// A plain fix for a TOML syntax error.
    public static func syntaxFix(for error: TOMLError) -> String {
        let m = error.message
        if m.contains("needs quotes") || m.contains("not closed with \"") || m.contains("not closed with '") {
            return "Put text in double quotes on one line, like: title = \"Disk\""
        }
        if m.contains("appears twice") { return "Keep one of the two lines." }
        if m.contains("list") { return "Close the list with ] and put commas between its items." }
        if m.contains("expected \"=\"") { return "Write one key = value per line." }
        return "Each line is key = value, with text in double quotes; see the README for examples."
    }

    static func jsonErrorSummary(_ error: Error) -> String {
        let text = "\(error)"
        if let range = text.range(of: "debugDescription: \"") {
            let rest = text[range.upperBound...]
            if let end = rest.firstIndex(of: "\"") { return String(rest[..<end]) }
        }
        return "unreadable"
    }

    static func validate(_ raw: [String: TOMLValue], lines rawLines: [String: Int] = [:], fileName: String, file: URL?) -> (WidgetConfig?, [ConfigIssue]) {
        let checked = ConfigSchema.widget.check(raw, lines: rawLines, fileName: fileName)
        var issues = checked.issues
        let table = checked.values
        let lines = checked.lines
        func warn(_ key: String, _ m: String, fix: String? = nil) {
            issues.append(ConfigIssue(file: fileName, line: lines[key], message: m, severity: .warning, fix: fix))
        }
        func error(_ key: String, _ m: String, fix: String? = nil) {
            issues.append(ConfigIssue(file: fileName, line: lines[key], message: m, severity: .error, fix: fix))
        }
        func text(_ key: String) -> String? {
            if case .string(let s)? = table[key] { return s }
            return nil
        }
        func flag(_ key: String) -> Bool? {
            if case .bool(let b)? = table[key] { return b }
            return nil
        }

        let id = Self.id(forFileName: fileName)
        let command = text("command")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if command?.isEmpty == true {
            error("command", "\"command\" is empty", fix: "Write the shell command to run, like: command = \"date +%H:%M\"")
        }

        var title = text("title")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            if raw.keys.contains(where: { ConfigSchema.widget.key(named: $0)?.name == "title" }) == false {
                warn("title", "\"title\" is missing; using \"\(id)\"", fix: "Add a line like: title = \"\(id.capitalized)\"")
            }
            title = id
        }

        var icon = text("icon")?.trimmingCharacters(in: .whitespaces) ?? defaultIcon
        if icon.isEmpty || !icon.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == ".") }) {
            warn("icon", "\"\(icon)\" is not an SF Symbol name (like \"cloud.sun\"); using \"\(defaultIcon)\"",
                 fix: "Use a name from the SF Symbols app, in lower case with dots, like icon = \"cloud.sun\"")
            icon = defaultIcon
        }

        var refresh = RefreshPolicy.onOpen
        if let v = table["refresh"] {
            if let parsed = RefreshPolicy.parse(v) {
                refresh = parsed.0
                if parsed.clamped {
                    warn("refresh", "refresh is raised to \(Int(RefreshPolicy.minimumInterval)) seconds, the shortest allowed",
                         fix: "Use refresh = \(Int(RefreshPolicy.minimumInterval)) or more, or signal = true to run only when asked.")
                }
            } else {
                warn("refresh", "refresh must be seconds (300), a duration (\"5m\") or \"on open\"; using \"on open\"",
                     fix: "Write it like refresh = \"5m\" or refresh = \"on open\".")
            }
        }

        let clickText = text("click")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let click = (clickText?.isEmpty ?? true) ? nil : clickText

        var timeout = defaultTimeout
        switch table["timeout"] {
        case .integer(let n)?: timeout = Double(n)
        case .float(let d)?: timeout = d
        default: break
        }

        var order = 0
        if case .integer(let n)? = table["order"] { order = n }
        let enabled = flag("enabled") ?? true
        var signal = flag("signal") ?? false
        let stream = flag("stream") ?? false
        let always = flag("always") ?? false
        let updates = text("updates").flatMap(WidgetUpdates.init(rawValue:)) ?? .whenShown

        if stream {
            if signal {
                warn("signal", "signal is ignored: a stream widget updates itself; `iceberg trigger` restarts it",
                     fix: "Remove signal = true, or remove stream = true to run the command once per signal.")
                signal = false
            }
            if table["refresh"] != nil {
                warn("refresh", "refresh is ignored for a stream widget, which prints a line whenever it has news",
                     fix: "Remove the refresh line, or remove stream = true to run the command on a schedule.")
                refresh = .onOpen
            }
            if table["timeout"] != nil {
                warn("timeout", "timeout does not apply to a stream widget, which keeps running",
                     fix: "Remove the timeout line.")
            }
        }

        if issues.contains(where: { $0.severity == .error }) { return (nil, issues) }
        let config = WidgetConfig(id: id, title: title, icon: icon, command: command ?? "", refresh: refresh,
                                  click: click, timeout: timeout, order: order, enabled: enabled,
                                  signal: signal, stream: stream, updates: updates, always: always, file: file)
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
