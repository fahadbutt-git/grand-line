import Foundation

/// A section header and its rows.
public struct ResultGroup: Sendable, Equatable, Identifiable {
    public let section: ResultSection
    public var rows: [LaunchResult]

    public var id: Int { section.rawValue }
}

/// Puts ranked results into sections: the best becomes the top hit, the rest go
/// to their own sections in the fixed order, each up to its limit.
public enum ResultGrouping {
    /// Whether a row is a good enough match to be the top hit: a fallback is not,
    /// nor a row found only by letters scattered through one of its keywords (a
    /// bookmark's host, say), which says little about what was meant.
    public static func canBeTopHit(_ result: LaunchResult) -> Bool {
        guard !result.isFallback else { return false }
        let match = result.match
        if match.alias != .none || match.title != nil { return true }
        if let keyword = match.keyword { return keyword != .fuzzy }
        return true
    }

    /// - Parameters:
    ///   - ranked: best first.
    ///   - topHit: whether to lift the best result into Top hit.
    ///   - limitScale: a prefix shows one provider, so its section may hold more.
    ///   - layout: the section order and row counts from Settings.
    public static func group(_ ranked: [LaunchResult], topHit: Bool = true, limitScale: Int = 1,
                             layout: ResultLayout = .current) -> [ResultGroup] {
        var buckets: [ResultSection: [LaunchResult]] = [:]
        var rest = ranked[...]
        if topHit, let best = ranked.first, canBeTopHit(best) {
            buckets[.topHit] = [best]
            rest = ranked.dropFirst()
        }
        for result in rest {
            let limit = layout.limit(result.section) * limitScale
            if buckets[result.section, default: []].count < limit {
                buckets[result.section, default: []].append(result)
            }
        }
        return layout.order.compactMap { section in
            guard let rows = buckets[section], !rows.isEmpty else { return nil }
            return ResultGroup(section: section, rows: rows)
        }
    }
}
