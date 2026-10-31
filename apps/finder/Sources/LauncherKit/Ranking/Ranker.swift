import Foundation

/// Gives each result its rank key and sorts them, best first.
public struct Ranker: Sendable {
    public let usage: UsageStore?
    public let aliases: AliasTable

    public init(usage: UsageStore? = nil, aliases: AliasTable = AliasTable()) {
        self.usage = usage
        self.aliases = aliases
    }

    public func key(for result: LaunchResult, folded: String, frecencies: [String: Double], learned: String? = nil) -> RankKey {
        let match = result.match
        let alias = min(match.alias, aliases.match(folded: folded, id: result.id, own: result.aliases))
        return RankKey(
            fallback: result.isFallback,
            alias: alias,
            title: match.title?.rawValue ?? 5,
            keyword: match.keyword?.rawValue ?? 5,
            frecency: frecencies[result.id] ?? 0,
            quality: match.quality,
            learned: learned != nil && learned == result.id && match.matched && !result.isFallback
        )
    }

    /// Ranked best first. Equal keys keep shorter titles first, then the providers' order.
    public func rank(_ results: [LaunchResult], query: LaunchQuery) -> [LaunchResult] {
        let frecencies = usage?.frecencies(for: query) ?? [:]
        let learned = usage?.abbreviation(for: query)
        let folded = TextFold.simple(query.term)
        var keyed = results.enumerated().map { offset, result -> (Int, LaunchResult) in
            var ranked = result
            ranked.rank = key(for: result, folded: folded, frecencies: frecencies, learned: learned)
            return (offset, ranked)
        }
        keyed.sort { a, b in
            if a.1.rank != b.1.rank { return a.1.rank < b.1.rank }
            if a.1.title.utf8.count != b.1.title.utf8.count { return a.1.title.utf8.count < b.1.title.utf8.count }
            return a.0 < b.0
        }
        return keyed.map { $0.1 }
    }
}
