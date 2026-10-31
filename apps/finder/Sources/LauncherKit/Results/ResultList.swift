import Foundation

/// The rows on screen and the selected one. Synchronous results replace the
/// list; results that arrive later are merged in without stealing the selection:
/// the selected row stays selected, the top hit is never replaced, no row already
/// shown disappears or changes order, and new rows in a section already on screen
/// go below the selected row. Only a section that was not on screen yet can open
/// above the selection, and then the selection moves with its row.
///
/// One exception: when the list may have a top hit but the first batch had none
/// good enough, and the person has not moved the selection yet, the first good
/// match to arrive becomes the top hit and is selected.
public struct ResultList: Sendable, Equatable {
    public private(set) var groups: [ResultGroup] = []
    public private(set) var selectedIndex: Int?
    var limitScale = 1
    /// Whether a late result may still open Top hit.
    var awaitsTopHit = false

    public init() {}

    public init(groups: [ResultGroup], limitScale: Int = 1, topHit: Bool = false) {
        self.groups = groups
        self.limitScale = limitScale
        selectedIndex = rows.isEmpty ? nil : 0
        awaitsTopHit = topHit && !groups.contains { $0.section == .topHit }
    }

    /// Every row in display order.
    public var rows: [LaunchResult] { groups.flatMap(\.rows) }

    public var selected: LaunchResult? {
        guard let selectedIndex else { return nil }
        let all = rows
        return selectedIndex < all.count ? all[selectedIndex] : nil
    }

    public var isEmpty: Bool { groups.isEmpty }

    /// The row Command+1…9 runs: the nth row on screen.
    public func row(shortcut number: Int) -> LaunchResult? {
        let all = rows
        guard number >= 1, number <= 9, number <= all.count else { return nil }
        return all[number - 1]
    }

    /// The shortcut number shown on a row, if it has one.
    public func shortcutNumber(of id: String) -> Int? {
        guard let index = rows.prefix(9).firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    public mutating func replace(with groups: [ResultGroup], limitScale: Int = 1, topHit: Bool = false) {
        self = ResultList(groups: groups, limitScale: limitScale, topHit: topHit)
    }

    public mutating func moveSelection(by delta: Int) {
        awaitsTopHit = false
        let count = rows.count
        guard count > 0 else { selectedIndex = nil; return }
        let current = selectedIndex ?? 0
        selectedIndex = min(max(current + delta, 0), count - 1)
    }

    public mutating func select(id: String) {
        awaitsTopHit = false
        if let index = rows.firstIndex(where: { $0.id == id }) { selectedIndex = index }
    }

    /// Merges ranked results that arrived after the first batch.
    public mutating func merge(_ incoming: [LaunchResult]) {
        guard !groups.isEmpty else {
            replace(with: ResultGrouping.group(incoming, limitScale: limitScale), limitScale: limitScale)
            return
        }
        var shown = Set(rows.map(\.id))
        if awaitsTopHit, let best = incoming.first(where: { !shown.contains($0.id) }), ResultGrouping.canBeTopHit(best) {
            awaitsTopHit = false
            groups.insert(ResultGroup(section: .topHit, rows: [best]), at: 0)
            selectedIndex = 0
            shown.insert(best.id)
        }
        let selectedID = selected?.id
        let selectedPosition = selectedIndex ?? -1
        for result in incoming where !shown.contains(result.id) {
            insert(result, frozenThrough: selectedPosition)
            shown.insert(result.id)
        }
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) { selectedIndex = index }
    }

    /// Puts one row in its section, by rank, but never at or above the frozen row.
    private mutating func insert(_ result: LaunchResult, frozenThrough frozen: Int) {
        let section = result.section == .topHit ? ResultSection.answers : result.section
        var start = 0
        for (g, group) in groups.enumerated() {
            if group.section == section {
                guard group.rows.count < section.limit * limitScale else { return }
                var position = group.rows.count
                for (r, row) in group.rows.enumerated() where start + r > frozen && result.rank < row.rank {
                    position = r
                    break
                }
                groups[g].rows.insert(result, at: position)
                return
            }
            if group.section > section {
                groups.insert(ResultGroup(section: section, rows: [result]), at: g)
                return
            }
            start += group.rows.count
        }
        groups.append(ResultGroup(section: section, rows: [result]))
    }
}
