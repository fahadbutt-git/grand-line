import Foundation
import IndexKit

/// Merges the two sources of a search: IndexKit's name matches come back at
/// once (R1) and lead; Spotlight's content matches (R2) follow without moving them.
public enum SearchResults {
    public static func names(_ matches: [IndexMatch], plan: SearchPlan) -> [String] {
        matches.map(\.path).filter { plan.accepts($0) }
    }

    public static func merge(names: [String], spotlight: [String], limit: Int = 2_000) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in names + spotlight where seen.insert(path).inserted {
            result.append(path)
            if result.count == limit { break }
        }
        return result
    }
}
