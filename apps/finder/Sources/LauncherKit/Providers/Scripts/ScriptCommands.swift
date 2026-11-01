import Foundation

/// A script command: an executable in ~/.config/grand-line/sight/scripts/,
/// named after its file without the extension ("downloads.sh" → "downloads").
public struct ScriptCommand: Sendable, Equatable {
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    /// Every executable file in the folder that is not hidden and whose name is one word.
    public static func scan(_ folder: String, fileManager: FileManager = .default) -> [ScriptCommand] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }
        var seen = Set<String>()
        return names.sorted().compactMap { file in
            let path = folder + "/" + file
            var isFolder: ObjCBool = false
            guard !file.hasPrefix("."), fileManager.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue,
                  fileManager.isExecutableFile(atPath: path) else { return nil }
            let name = ((file as NSString).deletingPathExtension).lowercased()
            guard !name.isEmpty, !name.contains(" "), seen.insert(name).inserted else { return nil }
            return ScriptCommand(name: name, path: path)
        }
    }
}

/// One row a script printed.
public struct ScriptRow: Sendable, Equatable, Decodable {
    public var title: String
    public var subtitle: String?
    /// An SF Symbol name.
    public var icon: String?
    /// What the script is given back when the row is chosen; the title when absent.
    public var value: String?
    /// Hidden words the row is also found by.
    public var keywords: [String]?

    public init(title: String, subtitle: String? = nil, icon: String? = nil, value: String? = nil, keywords: [String]? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.value = value
        self.keywords = keywords
    }
}

/// What a script answered.
public enum ScriptReply: Sendable, Equatable {
    /// Rows to show (again): the script goes on.
    case rows([ScriptRow])
    /// `{"close": true}`: done, the window closes.
    case close
    /// No rows and no close, a non-zero exit or a time-out: the message says which.
    case failed(String)
}

/// The protocol, after rofi's script mode: run with no arguments, a script
/// prints one JSON object per line, {"title", "subtitle", "icon", "value",
/// "keywords"}. Choosing a row runs the script again with the row's value as
/// its only argument (an argument list, never a shell line). Its answer is
/// either rows again, which replace the list, or a line {"close": true},
/// which closes the window. Lines that are not JSON objects with a title are
/// skipped. A script that runs past the time limit is stopped.
public enum ScriptOutput {
    struct Line: Decodable {
        var title: String?
        var subtitle: String?
        var icon: String?
        var value: String?
        var keywords: [String]?
        var close: Bool?
    }

    /// Rows past this are not read: a script printing without end does not
    /// fill the window (or the memory) with them.
    public static let maxRows = 1_000

    public static func parse(_ text: String, status: Int32 = 0) -> ScriptReply {
        let decoder = JSONDecoder()
        var rows: [ScriptRow] = []
        for raw in text.split(whereSeparator: \.isNewline) where rows.count < maxRows {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("{"), let decoded = try? decoder.decode(Line.self, from: Data(line.utf8)) else { continue }
            if decoded.close == true { return .close }
            guard let title = decoded.title, !title.isEmpty else { continue }
            rows.append(ScriptRow(title: title, subtitle: decoded.subtitle, icon: decoded.icon, value: decoded.value, keywords: decoded.keywords))
        }
        if !rows.isEmpty { return .rows(rows) }
        return .failed(status == 0 ? "The script printed no rows" : "The script stopped with status \(status)")
    }
}

/// One script command: "name " enters it and lists the rows it prints, more
/// words narrow them, and choosing a row runs it again with the row's value.
/// The rows of the current step are kept until you leave the command.
public final class ScriptCommandProvider: LaunchProvider, @unchecked Sendable {
    public let script: ScriptCommand
    public var id: String { ScriptCommandsProvider.providerID + ":" + script.name }
    public var title: String { script.name }
    public let symbol = "scroll"
    public let prefix: Prefix? = nil
    public var keyword: String? { script.name }
    public let routesBareKeyword = true
    public let inGlobalSearch = false
    let runner: any CommandRunning
    let timeout: TimeInterval
    private let lock = NSLock()
    private var page: [ScriptRow]?

    public init(_ script: ScriptCommand, runner: any CommandRunning, timeout: TimeInterval = 10) {
        self.script = script
        self.runner = runner
        self.timeout = timeout
    }

    /// Forgets the current step, so the next visit starts from the top.
    public func leave() { lock.withLock { page = nil } }

    var current: [ScriptRow]? { lock.withLock { page } }

    func run(_ arguments: [String]) async -> ScriptReply {
        do {
            let output = try await runner.run(script.path, arguments, timeout: timeout)
            let reply = ScriptOutput.parse(output.stdout, status: output.status)
            if output.truncated, case .failed = reply { return .failed("The script printed more than 1 MB and was stopped") }
            return reply
        } catch is CancellationError {
            return .failed("Stopped")
        } catch {
            return .failed("The script could not run: \(error.localizedDescription)")
        }
    }

    public func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        var rows = current
        if rows == nil {
            switch await run([]) {
            case .rows(let first):
                lock.withLock { page = first }
                rows = first
            case .close:
                return []
            case .failed(let why):
                try Task.checkCancellation()
                return [message(why)]
            }
        }
        try Task.checkCancellation()
        let all = (rows ?? []).enumerated().map { index, row in result(row, index: index) }
        guard !query.term.isEmpty else { return all }
        return Catalog(all.map { var r = $0; r.match = .unmatched; return r }).search(query.term)
    }

    /// Runs the script with the chosen value; new rows become the current step.
    public func choose(_ value: String) async -> ScriptReply {
        let reply = await run([value])
        switch reply {
        case .rows(let next): lock.withLock { page = next }
        case .close: leave()
        case .failed: break
        }
        return reply
    }

    func result(_ row: ScriptRow, index: Int) -> LaunchResult {
        let value = row.value ?? row.title
        return LaunchResult(
            id: "script:\(script.name):\(index):\(value)",
            title: row.title,
            subtitle: row.subtitle ?? "",
            icon: .symbol(row.icon ?? "chevron.right"),
            section: .grandLine,
            keywords: row.keywords ?? [],
            accessory: script.name,
            actions: [
                LaunchAction("Choose", symbol: "return", closesWindow: false, .script(path: script.path, value: value)),
                LaunchAction.copy(value, title: "Copy value"),
            ],
            providerID: ScriptCommandsProvider.providerID,
            // The script's own order.
            match: MatchInfo(title: .prefix, quality: 100_000 - index)
        )
    }

    func message(_ text: String) -> LaunchResult {
        LaunchResult(
            id: "script:\(script.name):message",
            title: text,
            subtitle: script.path,
            icon: .symbol("exclamationmark.triangle"),
            section: .grandLine,
            actions: [LaunchAction("Edit script", symbol: "pencil", .run("/usr/bin/open", arguments: ["-t", script.path]))],
            providerID: ScriptCommandsProvider.providerID,
            match: .answer
        )
    }
}

/// The script commands as rows ("downloads": Return types "downloads " to
/// enter it), and the list of commands each run on its own. Searching
/// anything outside a command leaves the one you were in.
public final class ScriptCommandsProvider: InstantProvider, @unchecked Sendable {
    public static let providerID = "scripts"
    public let id = ScriptCommandsProvider.providerID
    public let title = "Script commands"
    public let symbol = "scroll"
    public let prefix: Prefix? = nil
    public let extraPrefixes: [Prefix] = [.shell]
    public let inGlobalSearch = true
    let folder: String
    let runner: any CommandRunning
    private let lock = NSLock()
    private var commands: [ScriptCommandProvider] = []
    private let catalog = Catalog()

    public init(folder: String = GrandLinePaths().scripts, runner: any CommandRunning = ShellRunner()) {
        self.folder = folder
        self.runner = runner
    }

    public func reload() {
        replace(ScriptCommand.scan(folder))
    }

    public func replace(_ scripts: [ScriptCommand]) {
        let old = lock.withLock { commands }
        let providers = scripts.map { script in
            old.first { $0.script == script } ?? ScriptCommandProvider(script, runner: runner)
        }
        lock.withLock { commands = providers }
        catalog.replace(scripts.map { script in
            LaunchResult(
                id: "scriptcmd:" + script.name,
                title: script.name,
                subtitle: "Script command",
                icon: .symbol("scroll"),
                section: .grandLine,
                keywords: ["script"],
                accessory: "Script",
                actions: [
                    LaunchAction.complete(script.name + " ", title: "Enter"),
                    LaunchAction("Edit", symbol: "pencil", shortcut: KeyShortcut("e"), .run("/usr/bin/open", arguments: ["-t", script.path])),
                    LaunchAction("Show in Nexus", symbol: "folder", .reveal(script.path)),
                ],
                providerID: id
            )
        })
    }

    /// One provider per command, for the engine.
    public var providers: [ScriptCommandProvider] { lock.withLock { commands } }

    public func provider(path: String) -> ScriptCommandProvider? {
        providers.first { $0.script.path == path }
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        // Outside a command: the next visit to one starts from its first step.
        providers.forEach { $0.leave() }
        let own = query.prefix == .shell
        guard !query.term.isEmpty || own else { return [] }
        return catalog.search(query.term, exactOnly: query.prefix == .exact, limit: 40)
    }
}
