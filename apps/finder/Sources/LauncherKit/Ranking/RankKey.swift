import Foundation

/// The fixed rank order: fallbacks last, then exact alias, alias prefix, title
/// tier, keyword tier, learned frecency, and match quality. Smaller sorts first.
public struct RankKey: Hashable, Sendable, Comparable {
    public var fallback: Bool
    public var alias: AliasMatch
    /// MatchTier raw value, or 5 for no title match.
    public var title: Int
    public var keyword: Int
    public var frecency: Double
    public var quality: Int

    public static let unranked = RankKey(fallback: true, alias: .none, title: 5, keyword: 5, frecency: 0, quality: 0)

    public static func < (a: RankKey, b: RankKey) -> Bool {
        if a.fallback != b.fallback { return !a.fallback }
        if a.alias != b.alias { return a.alias < b.alias }
        if a.title != b.title { return a.title < b.title }
        if a.keyword != b.keyword { return a.keyword < b.keyword }
        if a.frecency != b.frecency { return a.frecency > b.frecency }
        return a.quality > b.quality
    }
}
