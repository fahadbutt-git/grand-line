import Foundation

/// A folder's manual order (R7): a list of names. Items not in the list (new
/// files) come after, by name.
public enum ManualOrder {
    public static func apply(_ order: [String], to items: [FileItem]) -> [FileItem] {
        var rank: [String: Int] = [:]
        for (i, name) in order.enumerated() where rank[name] == nil { rank[name] = i }
        let known = items.filter { rank[$0.name] != nil }.sorted { rank[$0.name, default: 0] < rank[$1.name, default: 0] }
        let fresh = items.filter { rank[$0.name] == nil }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return known + fresh
    }

    /// The new order after dragging `moving` to sit before the item at `index`
    /// of `current` (the order on screen). `index == current.count` drops at the end.
    public static func move(_ moving: [String], to index: Int, in current: [String]) -> [String] {
        let set = Set(moving)
        let before = current.prefix(max(0, min(index, current.count))).filter { !set.contains($0) }
        let after = current.dropFirst(max(0, min(index, current.count))).filter { !set.contains($0) }
        let present = Set(current)
        let kept = moving.filter { present.contains($0) }
        return before + kept + after
    }
}
