import Foundation
import IndexKit

/// How an alias matched the query.
public enum AliasMatch: Int, Hashable, Sendable, Comparable {
    case exact
    case prefix
    case none

    public static func < (lhs: AliasMatch, rhs: AliasMatch) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a result matched the query, filled in by its provider.
public struct MatchInfo: Hashable, Sendable {
    public var alias: AliasMatch
    /// nil when only a keyword matched.
    public var title: MatchTier?
    public var keyword: MatchTier?
    /// Breaks ties inside a tier; higher is better.
    public var quality: Int
    /// Matched parts of the title as UTF-16 offsets.
    public var highlights: [Range<Int>]

    public init(alias: AliasMatch = .none, title: MatchTier? = nil, keyword: MatchTier? = nil, quality: Int = 0, highlights: [Range<Int>] = []) {
        self.alias = alias
        self.title = title
        self.keyword = keyword
        self.quality = quality
        self.highlights = highlights
    }

    /// For answers and commands that match by being asked for: as good as an exact title.
    public static let answer = MatchInfo(title: .exact)
    public static let unmatched = MatchInfo()

    public var matched: Bool { alias != .none || title != nil || keyword != nil }
}
