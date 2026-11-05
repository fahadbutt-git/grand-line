import Foundation
import IndexKit

/// How a search result was found, best first.
public enum SearchSource: Int, Sendable, Comparable, CaseIterable {
    /// By name, from the name index (or read from a folder the index skips).
    case nameIndex
    /// By name, from Spotlight (a place the index does not cover, a filter query).
    case nameSpotlight
    /// Only by what is inside the file (Spotlight's kMDItemTextContent).
    case content

    public static func < (lhs: SearchSource, rhs: SearchSource) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where one result stands in relevance order (`SortField.relevance`).
public struct SearchRank: Sendable, Equatable {
    public var source: SearchSource
    /// The name index's tier; Spotlight's results count as substring matches.
    public var tier: MatchTier

    public init(source: SearchSource, tier: MatchTier = .substring) {
        self.source = source
        self.tier = tier
    }

    public var isInsideFile: Bool { source == .content }
}

/// The results of a search in relevance order, with how each was found.
public struct SearchHits: Sendable, Equatable {
    public private(set) var paths: [String] = []
    public private(set) var ranks: [String: SearchRank] = [:]

    public init() {}

    /// Adds a path once; the first source to find it keeps it.
    @discardableResult
    mutating func add(_ path: String, _ rank: SearchRank) -> Bool {
        guard ranks[path] == nil else { return false }
        ranks[path] = rank
        paths.append(path)
        return true
    }

    public var nameCount: Int { ranks.values.filter { !$0.isInsideFile }.count }
    public var insideFileCount: Int { ranks.values.filter(\.isInsideFile).count }
}

/// Merges the two sources of a search: IndexKit's name matches come back at
/// once (R1) and lead; Spotlight's results (R2) follow without moving them:
/// its name matches first, then the files found only by their contents.
/// With a plan, results from app data are dropped from both sources (see
/// `SearchPlan.keeps`).
public enum SearchResults {
    public static func names(_ matches: [IndexMatch], plan: SearchPlan) -> [String] {
        nameMatches(matches, plan: plan).map(\.path)
    }

    /// The name index's matches that belong to this search, in the index's order.
    public static func nameMatches(_ matches: [IndexMatch], plan: SearchPlan) -> [IndexMatch] {
        matches.filter { plan.accepts($0.path) && plan.keeps($0.path) }
    }

    /// Every result in relevance order, at most `limit`. Name matches are
    /// never crowded out by content matches: the limit cuts from the end.
    /// - Parameters:
    ///   - index: the name index's matches (already filtered with `nameMatches`).
    ///   - scanned: names read from folders the index skips (the Trash).
    ///   - spotlight: Spotlight's paths, newest first.
    public static func combine(
        index: [IndexMatch], scanned: [String] = [], spotlight: [String], plan: SearchPlan?, limit: Int = 2_000
    ) -> SearchHits {
        var hits = SearchHits()
        func full() -> Bool { hits.paths.count >= limit }
        for match in index where !full() { hits.add(match.path, SearchRank(source: .nameIndex, tier: match.tier)) }
        for path in scanned where !full() { hits.add(path, SearchRank(source: .nameIndex)) }
        var byName: [String] = []
        var byContent: [String] = []
        for path in spotlight {
            guard let plan else {
                byName.append(path)
                continue
            }
            guard plan.keeps(path) else { continue }
            if plan.matchesName(path) { byName.append(path) } else { byContent.append(path) }
        }
        for path in byName where !full() { hits.add(path, SearchRank(source: .nameSpotlight)) }
        for path in byContent where !full() { hits.add(path, SearchRank(source: .content)) }
        return hits
    }

    public static func merge(names: [String], spotlight: [String], plan: SearchPlan? = nil, limit: Int = 2_000) -> [String] {
        let index = names.map { IndexMatch(path: $0, name: ($0 as NSString).lastPathComponent, isFolder: false, tier: .substring, highlights: []) }
        return combine(index: index, spotlight: spotlight, plan: plan, limit: limit).paths
    }
}
