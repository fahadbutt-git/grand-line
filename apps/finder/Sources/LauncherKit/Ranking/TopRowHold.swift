import Foundation

/// Keeps the top row still while you type. Once a row has been shown on top
/// for a query, it stays on top as the query grows ("saf" → "safa"), as long
/// as it still matches and nothing in a strictly better tier has turned up
/// (a better alias, title or keyword tier, or the row learned for exactly what
/// was typed). A higher score alone never moves it, so Return does what the
/// person saw. Deleting letters or typing something else starts over.
public struct TopRowHold: Sendable, Equatable {
    /// The query (prefix and folded term) the top row was shown for.
    public private(set) var shownFor = ""
    public private(set) var topID: String?

    public init() {}

    public mutating func reset() {
        shownFor = ""
        topID = nil
    }

    /// `ranked` best first, with rank keys filled in. Returns them with the
    /// held row moved back to the top when it should stay, and remembers the
    /// row now on top.
    public mutating func apply(_ ranked: [LaunchResult], query: LaunchQuery) -> [LaunchResult] {
        let key = query.usageKey
        guard !query.term.isEmpty else {
            reset()
            return ranked
        }
        var result = ranked
        if let held = topID, !shownFor.isEmpty, key.hasPrefix(shownFor),
           let index = result.firstIndex(where: { $0.id == held }), index > 0,
           ResultGrouping.canBeTopHit(result[index]),
           !result[0].rank.hasBetterTier(than: result[index].rank) {
            let row = result.remove(at: index)
            result.insert(row, at: 0)
        }
        if let first = result.first, ResultGrouping.canBeTopHit(first) {
            topID = first.id
            shownFor = key
        } else {
            reset()
        }
        return result
    }
}
