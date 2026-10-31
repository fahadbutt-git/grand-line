import Foundation
import IndexKit

/// Merges the two sources of a search: IndexKit's name matches come back at
/// once (R1) and lead; Spotlight's content matches (R2) follow without moving them.
/// With a plan, Spotlight's name matches come before its content matches, and
/// results from app data are dropped from both sources (see `SearchPlan.keeps`).
public enum SearchResults {
    public static func names(_ matches: [IndexMatch], plan: SearchPlan) -> [String] {
        matches.map(\.path).filter { plan.accepts($0) && plan.keeps($0) }
    }

    public static func merge(names: [String], spotlight: [String], plan: SearchPlan? = nil, limit: Int = 2_000) -> [String] {
        var ordered = spotlight
        if let plan {
            var byName: [String] = []
            var byContent: [String] = []
            for path in spotlight where plan.keeps(path) {
                if plan.matchesName(path) {
                    byName.append(path)
                } else {
                    byContent.append(path)
                }
            }
            ordered = byName + byContent
        }
        var seen = Set<String>()
        var result: [String] = []
        for path in names + ordered where seen.insert(path).inserted {
            result.append(path)
            if result.count == limit { break }
        }
        return result
    }
}
