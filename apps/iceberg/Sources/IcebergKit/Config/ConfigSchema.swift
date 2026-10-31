import Foundation

/// The kind of value a key takes.
public enum SchemaType: Equatable, Sendable {
    /// Text in quotes.
    case text
    /// An SF Symbol name, in quotes.
    case symbol
    case bool
    /// A whole number.
    case integer
    /// A number (whole or not).
    case number
    /// A number of seconds, or a duration such as "30s" or "5m".
    case seconds
    /// Seconds, a duration, or "on open".
    case refresh
    /// One of a few words, in quotes.
    case choice([String])
    /// A list of names in quotes.
    case names
    /// A keyboard shortcut such as "ctrl+option+cmd+n", or "" for none.
    case shortcut

    /// What the value must be, for messages.
    var expectation: String {
        switch self {
        case .text, .symbol: return "text in quotes"
        case .bool: return "true or false"
        case .integer: return "a whole number"
        case .number: return "a number"
        case .seconds: return "a number of seconds or a duration such as \"30s\""
        case .refresh: return "seconds (300), a duration (\"5m\") or \"on open\""
        case .choice(let words): return "one of " + words.map { "\"\($0)\"" }.joined(separator: ", ")
        case .names: return "a list of names in quotes, such as [\"date\", \"today\"]"
        case .shortcut: return "a shortcut such as \"ctrl+option+cmd+n\", or \"\" for none"
        }
    }
}

/// One key a file may set.
public struct SchemaKey: Equatable, Sendable {
    public var name: String
    public var type: SchemaType
    /// One line on what it does (also the schema's description).
    public var summary: String
    /// The value as it would be written in TOML, for fixes and the docs.
    public var example: String
    /// The default as written in TOML, nil when there is none.
    public var defaultValue: String?
    public var range: ClosedRange<Double>?
    /// Out of range: true keeps the nearest allowed value, false ignores the
    /// value (the default is used).
    public var clamps: Bool
    /// Other names accepted for this key (older names, Waybar's and SketchyBar's).
    public var aliases: [String]
    /// A file without it cannot be used.
    public var required: Bool

    public init(_ name: String, _ type: SchemaType, _ summary: String, example: String, defaultValue: String? = nil,
                range: ClosedRange<Double>? = nil, clamps: Bool = false, aliases: [String] = [], required: Bool = false) {
        self.name = name
        self.type = type
        self.summary = summary
        self.example = example
        self.defaultValue = defaultValue
        self.range = range
        self.clamps = clamps
        self.aliases = aliases
        self.required = required
    }
}

/// The keys a file may hold, their types and ranges. Both iceberg.toml and
/// widget files are checked against one of these on every load; the same
/// table is published as `Resources/Iceberg/iceberg.schema.json` for
/// editors, and a test keeps the two the same.
public struct ConfigSchema: Sendable {
    /// What the file is, for messages ("a widget file").
    public var noun: String
    public var keys: [SchemaKey]

    public init(noun: String, keys: [SchemaKey]) {
        self.noun = noun
        self.keys = keys
    }

    /// The key by its name or one of its aliases.
    public func key(named name: String) -> SchemaKey? {
        keys.first { $0.name == name } ?? keys.first { $0.aliases.contains(name) }
    }

    public var names: [String] { keys.map(\.name) }

    /// What a check found: the values that can be used (by canonical key,
    /// seconds and durations already read, choices in lower case, ranges
    /// applied), their lines, and the problems.
    public struct Checked: Sendable {
        public var values: [String: TOMLValue] = [:]
        public var lines: [String: Int] = [:]
        public var issues: [ConfigIssue] = []
    }

    public func check(_ raw: [String: TOMLValue], lines: [String: Int] = [:], fileName: String) -> Checked {
        var out = Checked()
        // In file order, so "the first one" means the one higher up.
        let ordered = raw.keys.sorted { a, b in
            let la = lines[a] ?? Int.max, lb = lines[b] ?? Int.max
            return la != lb ? la < lb : a < b
        }
        var present: Set<String> = []
        for rawKey in ordered {
            let value = raw[rawKey]!
            let line = lines[rawKey]
            guard let spec = self.key(named: rawKey) else {
                if let guess = WidgetConfig.closest(to: rawKey, in: names) {
                    out.issues.append(ConfigIssue(file: fileName, line: line,
                                                  message: "unknown key \"\(rawKey)\" (did you mean \"\(guess)\"?)",
                                                  severity: .warning, fix: "Rename it to \(guess)."))
                } else {
                    out.issues.append(ConfigIssue(file: fileName, line: line, message: "unknown key \"\(rawKey)\" is ignored",
                                                  severity: .warning,
                                                  fix: "Remove the line. The keys \(noun) takes are listed in iceberg.schema.json and the README."))
                }
                continue
            }
            if present.contains(spec.name) {
                out.issues.append(ConfigIssue(file: fileName, line: line,
                                              message: "\"\(rawKey)\" repeats \"\(spec.name)\"; the first one is used",
                                              severity: .warning, fix: "Keep one of the two lines."))
                continue
            }
            present.insert(spec.name)
            switch Self.read(value, as: spec) {
            case .ok(let v, let note):
                out.values[spec.name] = v
                if let line { out.lines[spec.name] = line }
                if let note {
                    out.issues.append(ConfigIssue(file: fileName, line: line, message: note.message, severity: .warning, fix: note.fix))
                }
            case .bad(let message, let fix):
                out.issues.append(ConfigIssue(file: fileName, line: line, message: message,
                                              severity: spec.required ? .error : .warning, fix: fix))
            }
        }
        for key in keys where key.required && !raw.keys.contains(where: { self.key(named: $0)?.name == key.name }) {
            out.issues.append(ConfigIssue(file: fileName, message: "\"\(key.name)\" is missing: \(key.summary.lowercasedFirst)",
                                          severity: .error, fix: "Add a line like: \(key.name) = \(key.example)"))
        }
        return out
    }

    enum Reading {
        case ok(TOMLValue, note: (message: String, fix: String)?)
        case bad(String, fix: String)
    }

    static func read(_ value: TOMLValue, as key: SchemaKey) -> Reading {
        let name = key.name
        func wrong() -> Reading {
            let fix: String
            switch key.type {
            case .bool: fix = "Write \(name) = true or \(name) = false, without quotes."
            case .text, .symbol, .choice, .shortcut: fix = "Put the value in double quotes, like: \(name) = \(key.example)"
            default: fix = "Write it like: \(name) = \(key.example)"
            }
            let found = value.kindName
            return .bad("\"\(name)\" must be \(key.type.expectation), not \(found)", fix: fix)
        }
        switch key.type {
        case .text, .symbol:
            guard case .string = value else { return wrong() }
            return .ok(value, note: nil)
        case .bool:
            guard case .bool = value else { return wrong() }
            return .ok(value, note: nil)
        case .names:
            guard case .array = value else { return wrong() }
            return .ok(value, note: nil)
        case .refresh:
            // Read by RefreshPolicy, which also raises intervals that are too short.
            switch value {
            case .integer, .float, .string: return .ok(value, note: nil)
            default: return wrong()
            }
        case .choice(let words):
            guard case .string(let s) = value else { return wrong() }
            let word = s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "-", with: "_")
            guard words.contains(word) else {
                return .bad("\"\(name)\" must be \(key.type.expectation), not \"\(s)\"",
                            fix: "Use one of: " + words.map { "\(name) = \"\($0)\"" }.joined(separator: " or ") + ".")
            }
            return .ok(.string(word), note: nil)
        case .shortcut:
            guard case .string(let s) = value else { return wrong() }
            let t = s.trimmingCharacters(in: .whitespaces).lowercased()
            if t.isEmpty || t == "none" || t == "off" { return .ok(.string(""), note: nil) }
            guard let shortcut = KeyShortcut.parse(t) else {
                return .bad("\"\(s)\" is not a shortcut Iceberg can use",
                            fix: "Write ctrl, option, cmd or shift (at least one besides shift) and a key, joined with +, like \(name) = \(key.example). Use \"\" for none.")
            }
            return .ok(.string(shortcut.text), note: nil)
        case .integer, .number, .seconds:
            var number: Double?
            switch value {
            case .integer(let n): number = Double(n)
            case .float(let d): number = d
            case .string(let s) where key.type == .seconds: number = RefreshPolicy.parseDuration(s.lowercased())
            default: number = nil
            }
            guard let n = number, n.isFinite else { return wrong() }
            if key.type == .integer, n.rounded() != n || abs(n) > 1e15 { return wrong() }
            guard let range = key.range, !range.contains(n) else {
                return .ok(key.type == .integer ? .integer(Int(n)) : .float(n), note: nil)
            }
            let span = "\(format(range.lowerBound)) to \(format(range.upperBound))"
            if key.clamps {
                let kept = min(max(n, range.lowerBound), range.upperBound)
                return .ok(key.type == .integer ? .integer(Int(kept)) : .float(kept),
                           note: (message: "\"\(name)\" is kept between \(format(range.lowerBound)) and \(format(range.upperBound)); using \(format(kept))",
                                  fix: "Use a value from \(span)."))
            }
            let fallback = key.defaultValue.map { "; using \($0)" } ?? ""
            return .bad("\"\(name)\" must be between \(format(range.lowerBound)) and \(format(range.upperBound))\(fallback)",
                        fix: "Use a value from \(span).")
        }
    }

    /// 3 as "3", 0.12 as "0.12".
    static func format(_ d: Double) -> String {
        if d.rounded() == d, abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }
}

extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}

// MARK: The two schemas

extension ConfigSchema {
    /// `~/.config/grand-line/iceberg/iceberg.toml`.
    public static let settings = ConfigSchema(noun: "iceberg.toml", keys: [
        SchemaKey("panel", .names, "What the panel shows, in order: built-in items and widget file names.",
                  example: "[\"date\", \"now-playing\", \"today\"]", defaultValue: "[\"date\", \"now-playing\", \"today\"]"),
        SchemaKey("open_on", .choice(["hover", "click"]), "Open the panel when the pointer rests on the notch, or when it is clicked.",
                  example: "\"hover\"", defaultValue: "\"hover\""),
        SchemaKey("hover_delay", .number, "Seconds the pointer rests on the notch before the panel opens.",
                  example: "0.12", defaultValue: "0.12", range: 0...3),
        SchemaKey("close_delay", .number, "Seconds after the pointer leaves before the panel closes.",
                  example: "0.35", defaultValue: "0.35", range: 0...3),
        SchemaKey("toggle_shortcut", .shortcut, "A keyboard shortcut that opens or closes the panel from any app.",
                  example: "\"ctrl+option+cmd+n\"", defaultValue: "\"ctrl+option+cmd+n\""),
        SchemaKey("external_displays", .choice(["none", "pill"]), "Displays without a notch: nothing, or a pill at the top centre.",
                  example: "\"none\"", defaultValue: "\"none\""),
        SchemaKey("live_activity", .bool, "Artwork and playing bars beside the closed notch while music plays.",
                  example: "true", defaultValue: "true"),
        SchemaKey("menu_bar_icon", .bool, "Iceberg's item in the menu bar.", example: "true", defaultValue: "true"),
        SchemaKey("launch_at_login", .bool, "Open Iceberg when you log in.", example: "true", defaultValue: "true"),
        SchemaKey("max_concurrent", .integer, "The most widget commands that run at the same moment (and the most streams).",
                  example: "4", defaultValue: "4", range: 1...16, clamps: true),
        SchemaKey("builtin", .names, "The older way to choose built-in items; panel replaces it.",
                  example: "[\"now-playing\", \"today\"]"),
    ])

    /// A widget file in `~/.config/grand-line/iceberg/widgets/`.
    public static let widget = ConfigSchema(noun: "a widget file", keys: [
        SchemaKey("command", .text, "The shell command whose output is shown.",
                  example: "\"date +%H:%M\"", aliases: ["script", "exec"], required: true),
        SchemaKey("title", .text, "The label. Defaults to the file name.", example: "\"Disk\""),
        SchemaKey("icon", .symbol, "An SF Symbol name.", example: "\"internaldrive\"", defaultValue: "\"square.dashed\"",
                  aliases: ["symbol", "sf_symbol"]),
        SchemaKey("refresh", .refresh, "How often it runs: seconds, a duration such as \"5m\", or \"on open\".",
                  example: "\"5m\"", defaultValue: "\"on open\"", aliases: ["interval", "update_freq"]),
        SchemaKey("signal", .bool, "Runs when `iceberg trigger NAME` is called (and once as the panel opens).",
                  example: "true", defaultValue: "false"),
        SchemaKey("stream", .bool, "The command keeps running and prints one line per update.",
                  example: "true", defaultValue: "false"),
        SchemaKey("updates", .choice(["when_shown", "always"]),
                  "\"when_shown\" runs it only while the panel is open; \"always\" keeps it current while closed.",
                  example: "\"when_shown\"", defaultValue: "\"when_shown\""),
        SchemaKey("always", .bool, "Keep running during Low Power Mode and around sleep.", example: "false", defaultValue: "false"),
        SchemaKey("click", .text, "Run when the widget is clicked, then the widget refreshes.",
                  example: "\"open -a 'Disk Utility'\"", aliases: ["on_click", "on-click", "click_command"]),
        SchemaKey("timeout", .seconds, "Seconds before a stuck command and everything it started are stopped.",
                  example: "10", defaultValue: "10", range: 1...120, clamps: true),
        SchemaKey("order", .integer, "Only for files from before panel: the position, lowest first.", example: "0", defaultValue: "0"),
        SchemaKey("enabled", .bool, "false keeps it off, whatever Settings says.", example: "true", defaultValue: "true"),
    ])
}

/// Finds the line of each key in a JSON widget file, so its problems can
/// name a line too.
public enum JSONKeyLines {
    public static func lines(in text: String) -> [String: Int] {
        var out: [String: Int] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var rest = Substring(line)
            while let open = rest.firstIndex(of: "\"") {
                let afterOpen = rest.index(after: open)
                guard let close = rest[afterOpen...].firstIndex(of: "\"") else { break }
                let name = String(rest[afterOpen..<close])
                let after = rest[rest.index(after: close)...].drop { $0 == " " || $0 == "\t" }
                if after.first == ":", out[name] == nil { out[name] = index + 1 }
                rest = rest[rest.index(after: close)...]
            }
        }
        return out
    }
}
