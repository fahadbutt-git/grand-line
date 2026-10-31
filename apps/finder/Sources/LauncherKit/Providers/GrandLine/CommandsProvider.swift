import Foundation

/// The package's own commands, by their summary lines. A command that takes
/// arguments completes to "name " and then shows what it will run, or the
/// choices of a dropdown argument.
public final class CommandsProvider: InstantProvider, @unchecked Sendable {
    public let id = "commands"
    public let title = "Grand Line commands"
    public let symbol = "terminal"
    public let prefix: Prefix? = nil
    public let extraPrefixes: [Prefix] = [.shell]
    public let inGlobalSearch = true
    let folder: String
    let catalog = Catalog()
    private let lock = NSLock()
    private var scripts: [String: CommandScript] = [:]

    public init(folder: String = GrandLinePaths().bin) {
        self.folder = folder
    }

    public func reload() {
        replace(CommandScript.scan(folder))
    }

    public func replace(_ list: [CommandScript]) {
        lock.lock()
        scripts = Dictionary(list.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        lock.unlock()
        catalog.replace(list.map(Self.row))
    }

    static func row(_ script: CommandScript) -> LaunchResult {
        let primary: LaunchAction = script.arguments.isEmpty
            ? LaunchAction("Run", symbol: "play", .run(script.path, arguments: []))
            : LaunchAction.complete(script.name + " ", title: "Enter arguments")
        return LaunchResult(
            id: "cmd:" + script.name,
            title: script.name,
            subtitle: script.arguments.isEmpty ? script.summary : script.summary + " · " + script.usage,
            icon: .symbol("terminal"),
            section: .grandLine,
            keywords: [script.summary],
            actions: [
                primary,
                LaunchAction("Run in a terminal window", symbol: "macwindow", .run(GrandLinePaths().command("in-window"), arguments: [script.path])),
                LaunchAction("Edit", symbol: "pencil", shortcut: KeyShortcut("e"), .run("/usr/bin/open", arguments: ["-t", script.path])),
                LaunchAction.copy(script.path, title: "Copy path"),
                .favourite,
            ],
            providerID: "commands"
        )
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard !query.term.isEmpty else { return [] }
        // "transcode " with nothing after it already lists the choices.
        let typedSpace = query.raw.hasSuffix(" ") && !query.term.contains(" ")
        if let split = query.keywordSplit ?? (typedSpace ? (keyword: query.term.lowercased(), rest: "") : nil) {
            lock.lock()
            let script = scripts[split.keyword]
            lock.unlock()
            if let script, !script.arguments.isEmpty {
                return Self.invocation(script, text: split.rest)
            }
        }
        return catalog.search(query.term, exactOnly: query.prefix == .exact, limit: 40)
    }

    /// The rows for a command with arguments typed after it.
    public static func invocation(_ script: CommandScript, text: String) -> [LaunchResult] {
        let values = ArgumentSplitter.split(text, count: script.arguments.count)
        // A dropdown whose value is not one of its choices lists the choices.
        for (i, spec) in script.arguments.enumerated() where spec.type == .dropdown {
            let typed = i < values.count ? values[i] : ""
            if spec.data.contains(typed) { continue }
            let before = values.prefix(i).joined(separator: ", ")
            let options = spec.data.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed.lowercased()) }
            return options.map { option in
                let filled = (before.isEmpty ? "" : before + ", ") + option
                let completion = script.name + " " + filled + (i < script.arguments.count - 1 ? ", " : "")
                return LaunchResult(
                    id: "cmd:\(script.name):\(i):\(option)",
                    title: option,
                    subtitle: "\(script.name): \(spec.placeholder)",
                    icon: .symbol("list.bullet"),
                    section: .grandLine,
                    actions: i == script.arguments.count - 1
                        ? [LaunchAction("Run", symbol: "play", .run(script.path, arguments: Array(values.prefix(i)) + [option]))]
                        : [LaunchAction.complete(completion)],
                    providerID: "commands",
                    match: .answer
                )
            }
        }
        let missing = script.arguments.enumerated().contains { i, spec in !spec.optional && (i >= values.count || values[i].isEmpty) }
        let shown = values.map { "“\($0)”" }.joined(separator: " ")
        return [LaunchResult(
            id: "cmd:\(script.name):run",
            title: missing ? script.usage : "\(script.name) \(shown)",
            subtitle: missing ? "Type the arguments, separated by commas" : script.summary,
            icon: .symbol("terminal"),
            section: .grandLine,
            actions: missing ? [] : [
                LaunchAction("Run", symbol: "play", .run(script.path, arguments: values.filter { !$0.isEmpty })),
                LaunchAction.copy(ShellQuote.line([script.name] + values), title: "Copy command"),
            ],
            providerID: "commands",
            match: .answer
        )]
    }
}
