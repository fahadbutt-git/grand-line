import Foundation

/// A provider that is any program printing JSON lines, set up in
/// ~/.config/grand-line/sight/providers.tsv:
///
///     keyword TAB title TAB command TAB global (yes/no)
///
/// The query is passed as the last argument (and in SIGHT_QUERY). Each output
/// line is one row: {"title": …, "subtitle": …, "icon": "SF Symbol", "id": …,
/// "keywords": […], "accessory": …, "preview": "/path", and one of "open",
/// "url", "run", "copy", "paste" or "query"}, or "actions": [{"title": …, "open": …}, …].
public struct ExternalProviderConfig: Sendable, Equatable {
    public let keyword: String
    public let title: String
    public let command: String
    public let global: Bool

    public static func parse(_ text: String) -> [ExternalProviderConfig] {
        TSV.rows(text).compactMap { row in
            guard row.count >= 3, !row[0].isEmpty, !row[2].isEmpty else { return nil }
            let global = row.count > 3 && ["yes", "true", "1"].contains(row[3].lowercased())
            return ExternalProviderConfig(keyword: row[0].lowercased(), title: row[1].isEmpty ? row[0] : row[1], command: row[2], global: global)
        }
    }
}

public enum JSONLines {
    struct Line: Decodable {
        var id: String?
        var title: String?
        var subtitle: String?
        var icon: String?
        var keywords: [String]?
        var accessory: String?
        var preview: String?
        var open: String?
        var url: String?
        var run: String?
        var copy: String?
        var paste: String?
        var query: String?
        var actions: [ActionLine]?
    }

    struct ActionLine: Decodable {
        var title: String?
        var open: String?
        var url: String?
        var run: String?
        var copy: String?
        var paste: String?
        var query: String?
    }

    static func action(open: String?, url: String?, run: String?, copy: String?, paste: String?, query: String?) -> (String, ActionCommand)? {
        if let open { return ("Open", open.contains("://") ? .openURL(open, bundleID: nil) : .open(open)) }
        if let url { return ("Open", .openURL(url, bundleID: nil)) }
        if let run { return ("Run", .shell(run)) }
        if let copy { return ("Copy", .copyText(copy)) }
        if let paste { return ("Paste", .paste(paste)) }
        if let query { return ("Complete", .setQuery(query)) }
        return nil
    }

    /// Rows from the output, in order. Lines that are not JSON objects with a title are skipped.
    public static func parse(_ output: String, providerID: String, paths: GrandLinePaths = GrandLinePaths()) -> [LaunchResult] {
        let decoder = JSONDecoder()
        var rows: [LaunchResult] = []
        for (n, raw) in output.split(separator: "\n").enumerated() {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)), let title = line.title, !title.isEmpty else { continue }
            var actions: [LaunchAction] = []
            if let main = action(open: line.open, url: line.url, run: line.run, copy: line.copy, paste: line.paste, query: line.query) {
                actions.append(LaunchAction(main.0, symbol: "arrow.up.forward", closesWindow: !isQuery(main.1), main.1))
            }
            for extra in line.actions ?? [] {
                guard let more = action(open: extra.open, url: extra.url, run: extra.run, copy: extra.copy, paste: extra.paste, query: extra.query) else { continue }
                actions.append(LaunchAction(extra.title ?? more.0, symbol: "arrow.up.forward", closesWindow: !isQuery(more.1), more.1))
            }
            rows.append(LaunchResult(
                id: "\(providerID):" + (line.id ?? title),
                title: title,
                subtitle: line.subtitle ?? "",
                icon: .symbol(line.icon ?? "puzzlepiece.extension"),
                section: .system,
                keywords: line.keywords ?? [],
                accessory: line.accessory ?? "",
                actions: actions,
                previewPath: line.preview.map(paths.expand),
                providerID: providerID,
                match: MatchInfo(title: .wordStart, quality: 10_000 - n)
            ))
        }
        return rows
    }

    static func isQuery(_ command: ActionCommand) -> Bool {
        if case .setQuery = command { return true }
        return false
    }
}

public final class ExternalProvider: LaunchProvider, @unchecked Sendable {
    public let config: ExternalProviderConfig
    public var id: String { "ext:" + config.keyword }
    public var title: String { config.title }
    public let symbol = "puzzlepiece.extension"
    public let prefix: Prefix? = nil
    public var keyword: String? { config.keyword }
    public var inGlobalSearch: Bool { config.global }
    let runner: ShellRunner
    let paths: GrandLinePaths
    let timeout: TimeInterval

    public init(_ config: ExternalProviderConfig, runner: ShellRunner = ShellRunner(), paths: GrandLinePaths = GrandLinePaths(), timeout: TimeInterval = 3) {
        self.config = config
        self.runner = runner
        self.paths = paths
        self.timeout = timeout
    }

    public func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        guard !query.term.isEmpty else { return [] }
        var runner = self.runner
        runner.environment["SIGHT_QUERY"] = query.term
        // The command runs through bash, so it may use ~, $HOME and arguments of its own.
        let line = paths.expand(config.command) + " " + ShellQuote.quote(query.term)
        let output = try await runner.run("/bin/bash", ["-c", line], timeout: timeout)
        return JSONLines.parse(output.stdout, providerID: id, paths: paths)
    }
}
