import Foundation

/// The selected rows of a pane, by item id, with Finder's click and arrow rules.
/// `order` is always the ids as shown on screen.
public struct SelectionModel: Equatable, Sendable {
    public private(set) var selected: Set<String> = []
    /// Where a Shift range starts.
    public private(set) var anchor: String?
    /// The row the arrows move from.
    public private(set) var cursor: String?

    public init() {}

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }

    public func contains(_ id: String) -> Bool { selected.contains(id) }

    /// The selection in screen order.
    public func ordered(in order: [String]) -> [String] {
        order.filter { selected.contains($0) }
    }

    /// A plain click.
    public mutating func select(_ id: String) {
        selected = [id]
        anchor = id
        cursor = id
    }

    /// Selects exactly these, as after a reveal or a paste.
    public mutating func set(_ ids: [String], in order: [String]) {
        let wanted = Set(ids)
        selected = Set(order.filter { wanted.contains($0) })
        let first = order.first { selected.contains($0) }
        anchor = first
        cursor = first
    }

    /// Cmd+click.
    public mutating func toggle(_ id: String) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        anchor = id
        cursor = id
    }

    /// Shift+click: everything from the anchor to here.
    public mutating func extend(to id: String, in order: [String]) {
        guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
            select(id)
            return
        }
        selected = Set(order[min(from, to)...max(from, to)])
        cursor = id
    }

    /// Arrow keys. `step` is 1 in lists and the number of columns for Up and
    /// Down in the icon grid. With Shift the range from the anchor grows.
    public mutating func move(by step: Int, in order: [String], extending: Bool = false) {
        guard !order.isEmpty else { return }
        let start: Int
        if let cursor, let index = order.firstIndex(of: cursor) {
            start = index + step
        } else {
            start = step > 0 ? 0 : order.count - 1
        }
        let target = order[max(0, min(order.count - 1, start))]
        if extending {
            if anchor == nil { anchor = cursor ?? target }
            extend(to: target, in: order)
        } else {
            select(target)
        }
    }

    public mutating func selectAll(_ order: [String]) {
        selected = Set(order)
        anchor = order.first
        cursor = order.last
    }

    public mutating func clear() {
        selected = []
        anchor = nil
        cursor = nil
    }

    /// Drops ids that are no longer shown, after the folder changed.
    public mutating func prune(to order: [String]) {
        let shown = Set(order)
        selected = selected.intersection(shown)
        if let anchor, !shown.contains(anchor) { self.anchor = nil }
        if let cursor, !shown.contains(cursor) { self.cursor = nil }
    }
}
