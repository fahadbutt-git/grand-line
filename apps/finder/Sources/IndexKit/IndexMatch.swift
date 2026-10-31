import Foundation

/// How a name matched, best first.
public enum MatchTier: Int, Sendable, Comparable, CaseIterable {
    /// The whole name, or the name without its extension.
    case exact
    case prefix
    /// The start of a word: after a space, _, -, . or at a camelCase hump.
    case wordStart
    case substring
    /// The letters in order, the first at a word start: "gl rev" finds "Glaucoma Review".
    case fuzzy

    public static func < (lhs: MatchTier, rhs: MatchTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct IndexMatch: Sendable, Equatable {
    public let path: String
    public let name: String
    public let isFolder: Bool
    public let tier: MatchTier
    /// The matched parts of `name` as UTF-16 offsets, so `NSRange(range)` works in AppKit.
    public let highlights: [Range<Int>]

    public init(path: String, name: String, isFolder: Bool, tier: MatchTier, highlights: [Range<Int>]) {
        self.path = path
        self.name = name
        self.isFolder = isFolder
        self.tier = tier
        self.highlights = highlights
    }
}
