import Foundation
import IndexKit

/// The fixed rank order: fallbacks last, then a setting named by its whole
/// phrase, exact alias, alias prefix, exact and prefix titles, a row learned for
/// exactly this abbreviation, the other title tiers, the keyword tier, and last
/// a blend of fzf's match score and learned frecency. Smaller sorts first.
public struct RankKey: Hashable, Sendable, Comparable {
    public var fallback: Bool
    public var alias: AliasMatch
    /// A settings row ("setting.darkmode") whose whole phrase was typed ("dark
    /// mode", "wifi"): it changes the setting in place, so it comes before any
    /// other row that answers the same words: a menu entry or shortcut that
    /// runs something close to it, a pane, an app, a symbol, an alias.
    public var settingPhrase: Bool
    /// MatchTier raw value, or `noMatch` for no title match.
    public var title: Int
    public var keyword: Int
    public var frecency: Double
    public var quality: Int
    /// Picked last time this exact abbreviation was typed (LaunchBar's learning).
    public var learned: Bool

    public init(fallback: Bool, alias: AliasMatch, title: Int, keyword: Int, frecency: Double, quality: Int, learned: Bool = false,
                settingPhrase: Bool = false) {
        self.fallback = fallback
        self.alias = alias
        self.settingPhrase = settingPhrase
        self.title = title
        self.keyword = keyword
        self.frecency = frecency
        self.quality = quality
        self.learned = learned
    }

    /// The tier value of "did not match": after every MatchTier.
    public static let noMatch = MatchTier.allCases.count

    public static let unranked = RankKey(fallback: true, alias: .none, title: noMatch, keyword: noMatch, frecency: 0, quality: 0)

    /// How much one doubling of frecency is worth against fzf's score, where a
    /// matched letter is 16: a habit outweighs a slightly tidier match, not a
    /// much better one.
    public static let frecencyWeight = 12.0

    /// Exact and prefix titles (0) always come before everything else (1):
    /// learning may lift a row over fuzzier matches but never over these.
    public var band: Int { title <= MatchTier.prefix.rawValue ? 0 : 1 }

    /// fzf's score and frecency, blended (zoxide-style frecency on a log scale).
    public var blended: Double { Double(quality) + Self.frecencyWeight * log2(1 + max(0, frecency)) }

    /// Compares everything but the blended score: -1 when `a` is in a better
    /// tier, 1 when `b` is, 0 when they share one.
    static func compareTiers(_ a: RankKey, _ b: RankKey) -> Int {
        if a.fallback != b.fallback { return a.fallback ? 1 : -1 }
        if a.settingPhrase != b.settingPhrase { return a.settingPhrase ? -1 : 1 }
        if a.alias != b.alias { return a.alias < b.alias ? -1 : 1 }
        if a.band != b.band { return a.band < b.band ? -1 : 1 }
        if a.learned != b.learned { return a.learned ? -1 : 1 }
        if a.title != b.title { return a.title < b.title ? -1 : 1 }
        if a.keyword != b.keyword { return a.keyword < b.keyword ? -1 : 1 }
        return 0
    }

    /// Whether this key is in a strictly better tier than `other`: a better
    /// alias, title or keyword tier, or the learned row; not just a higher score.
    public func hasBetterTier(than other: RankKey) -> Bool {
        Self.compareTiers(self, other) < 0
    }

    public static func < (a: RankKey, b: RankKey) -> Bool {
        let tiers = compareTiers(a, b)
        if tiers != 0 { return tiers < 0 }
        let x = a.blended, y = b.blended
        if x != y { return x > y }
        return a.quality > b.quality
    }
}
