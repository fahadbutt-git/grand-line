import Foundation

/// Your own short names for results, from ~/.config/grand-line/byakugan/aliases.tsv:
/// alias TAB target, where the target is a result id (app:/Applications/Safari.app),
/// a URL or a path. Typing an alias in full puts its target on top.
public struct AliasTable: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let alias: String
        public let target: String
    }

    public private(set) var entries: [Entry]
    let byTarget: [String: [String]]

    public init(entries: [Entry] = []) {
        self.entries = entries
        self.byTarget = Dictionary(grouping: entries, by: \.target).mapValues { $0.map(\.alias) }
    }

    public static func parse(_ text: String) -> AliasTable {
        var entries: [Entry] = []
        for row in TSV.rows(text) where row.count >= 2 {
            let alias = TextFold.simple(row[0])
            guard !alias.isEmpty, !row[1].isEmpty else { continue }
            entries.removeAll { $0.alias == alias }
            entries.append(Entry(alias: alias, target: row[1]))
        }
        return AliasTable(entries: entries)
    }

    /// How the folded term matches the aliases that point at `id`, and the
    /// result's own aliases (which providers give in lowercase).
    public func match(folded: String, id: String, own: [String]) -> AliasMatch {
        guard !folded.isEmpty else { return .none }
        var best = AliasMatch.none
        func consider(_ alias: String) {
            if alias == folded { best = .exact } else if best == .none, alias.hasPrefix(folded) { best = .prefix }
        }
        if let mine = byTarget[id] { mine.forEach(consider) }
        own.forEach(consider)
        return best
    }

    /// Aliases whose target is not a result id: URLs and paths become rows of their own.
    public var standalone: [Entry] {
        entries.filter { $0.target.contains("://") || $0.target.hasPrefix("/") || $0.target.hasPrefix("~") }
    }
}
