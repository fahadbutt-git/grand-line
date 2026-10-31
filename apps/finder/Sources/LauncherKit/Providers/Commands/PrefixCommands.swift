import Foundation

/// `!` a new reminder: "call Smith in 20 min", "pay rent 2h", "submit at 3pm".
public struct ReminderProvider: InstantProvider {
    public let id = "reminder"
    public let title = "Reminder"
    public let symbol = "bell"
    public let prefix: Prefix? = .reminder
    public let inGlobalSearch = false
    let paths: GrandLinePaths
    let now: @Sendable () -> Date
    let calendar: Calendar
    public static let defaultMinutes = 30

    public init(paths: GrandLinePaths = GrandLinePaths(), calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.calendar = calendar
        self.now = now
    }

    /// The text and the minutes from now. A trailing time is read off the end.
    public func parse(_ text: String) -> (text: String, minutes: Int, given: Bool) {
        var words = text.split(separator: " ").map(String.init)
        func finish(_ minutes: Int, dropping count: Int) -> (String, Int, Bool) {
            words.removeLast(count)
            if words.last?.lowercased() == "in" { words.removeLast() }
            return (words.joined(separator: " "), max(1, minutes), true)
        }
        if words.count >= 2, words[words.count - 2].lowercased() == "at", let clock = DateMath.clock(words.last!.lowercased()) {
            var target = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: now()) ?? now()
            if target <= now() { target = calendar.date(byAdding: .day, value: 1, to: target) ?? target }
            let minutes = Int((target.timeIntervalSince(now()) / 60).rounded(.up))
            return finish(minutes, dropping: 2)
        }
        if words.count >= 3, let n = Int(words[words.count - 2]), let scale = Self.scale(words.last!) {
            return finish(n * scale, dropping: 2)
        }
        if words.count >= 2, let last = words.last {
            if let n = Int(last) { return finish(n, dropping: 1) }
            let digits = last.prefix { $0.isNumber }
            if !digits.isEmpty, let n = Int(digits), let scale = Self.scale(String(last.dropFirst(digits.count))) {
                return finish(n * scale, dropping: 1)
            }
        }
        return (text, Self.defaultMinutes, false)
    }

    static func scale(_ unit: String) -> Int? {
        switch unit.lowercased() {
        case "m", "min", "mins", "minute", "minutes": return 1
        case "h", "hr", "hrs", "hour", "hours": return 60
        case "d", "day", "days": return 1_440
        default: return nil
        }
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard !query.term.isEmpty else {
            return [LaunchResult(id: "reminder", title: "Remind me to…", subtitle: "Type what, then a time: 20m, 2h, at 3pm", icon: .symbol("bell"), section: .answers, actions: [], providerID: id, match: .answer)]
        }
        let (text, minutes, given) = parse(query.term)
        let when = minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
        return [LaunchResult(
            id: "reminder",
            title: "Remind me to \(text)",
            subtitle: "In \(when)" + (given ? "" : " · add a time: 20m, 2h, at 3pm"),
            icon: .symbol("bell"),
            section: .answers,
            actions: [LaunchAction("Set reminder", symbol: "bell", .run(paths.command("reminder"), arguments: [text, String(minutes)]))],
            providerID: id,
            match: .answer
        )]
    }
}

/// `>` runs a shell command in its own terminal window, through in-window.
public struct ShellProvider: InstantProvider {
    public let id = "shell"
    public let title = "Shell"
    public let symbol = "terminal"
    public let prefix: Prefix? = .shell
    public let inGlobalSearch = false
    let paths: GrandLinePaths

    public init(paths: GrandLinePaths = GrandLinePaths()) {
        self.paths = paths
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard !query.term.isEmpty else { return [] }
        return [LaunchResult(
            id: "shell",
            title: query.term,
            subtitle: "Run in a terminal window (zsh)",
            icon: .symbol("terminal"),
            section: .answers,
            actions: [
                LaunchAction("Run", symbol: "play", .run(paths.command("in-window"), arguments: ["/bin/zsh", "-lc", query.term])),
                LaunchAction("Run without a window", symbol: "play.circle", .run("/bin/zsh", arguments: ["-lc", query.term])),
                .copy(query.term, title: "Copy command"),
            ],
            providerID: id,
            match: .answer
        )]
    }
}

/// `$` shows Maccy's clipboard history by pressing Maccy's own pop-up shortcut.
/// That is Maccy's default, ⇧⌘C: setup leaves it as it is
/// (steps/10-macos-defaults.sh), and Caps + Ctrl + V sends the same keys.
public struct ClipboardProvider: InstantProvider {
    public let id = "clipboard"
    public let title = "Clipboard history"
    public let symbol = "list.clipboard"
    public let prefix: Prefix? = .clipboard
    public let inGlobalSearch = false
    public static let maccyKeys = "⇧⌘C"
    let shortcut: KeyShortcut?

    public init(keys: String = ClipboardProvider.maccyKeys) {
        shortcut = KeyShortcut(parsing: keys)
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard let shortcut else { return [] }
        return [LaunchResult(
            id: "clipboard",
            title: "Clipboard history",
            subtitle: "Shows Maccy",
            icon: .symbol("list.clipboard"),
            section: .answers,
            keys: [shortcut.label],
            actions: [LaunchAction("Show", symbol: "list.clipboard", .pressKeys(shortcut))],
            providerID: id,
            match: .answer
        )]
    }
}

/// `/` lists the prefixes and the keyword providers. Return types the prefix.
public struct PrefixListProvider: InstantProvider {
    public let id = "prefixes"
    public let title = "Prefixes"
    public let symbol = "list.bullet"
    public let prefix: Prefix? = .providers
    public let inGlobalSearch = false
    let keywords: [(keyword: String, title: String)]

    public init(keywords: [(keyword: String, title: String)] = []) {
        self.keywords = keywords
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        var rows = Prefix.allCases.filter { $0 != .providers }.map { prefix in
            LaunchResult(
                id: "prefix:" + prefix.rawValue,
                title: prefix.title,
                icon: .symbol(prefix.symbol),
                section: .system,
                accessory: prefix.rawValue,
                actions: [LaunchAction.complete(prefix.rawValue, title: "Use")],
                providerID: id
            )
        }
        rows += keywords.map { entry in
            LaunchResult(
                id: "keyword:" + entry.keyword,
                title: entry.title,
                icon: .symbol("puzzlepiece.extension"),
                section: .system,
                accessory: entry.keyword,
                actions: [LaunchAction.complete(entry.keyword + " ", title: "Use")],
                providerID: id
            )
        }
        guard !query.term.isEmpty else { return rows }
        return Catalog(rows).search(query.term)
    }
}
