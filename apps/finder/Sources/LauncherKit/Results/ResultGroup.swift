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
    /// - Parameters:
    ///   - ranked: best first.
    ///   - topHit: whether to lift the best result into Top hit.
    ///   - limitScale: a prefix shows one provider, so its section may hold more.
    public static func group(_ ranked: [LaunchResult], topHit: Bool = true, limitScale: Int = 1) -> [ResultGroup] {
        var buckets: [ResultSection: [LaunchResult]] = [:]
        var rest = ranked[...]
        if topHit, let best = ranked.first, !best.isFallback {
            buckets[.topHit] = [best]
            rest = ranked.dropFirst()
        }
        for result in rest {
            let limit = result.section.limit * limitScale
            if buckets[result.section, default: []].count < limit {
                buckets[result.section, default: []].append(result)
            }
        }
        return ResultSection.allCases.compactMap { section in
            guard let rows = buckets[section], !rows.isEmpty else { return nil }
            return ResultGroup(section: section, rows: rows)
        }
    }
}
