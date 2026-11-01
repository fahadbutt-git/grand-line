import Foundation

/// Tab and Shift+Tab where they do not move between panes (one pane, or a view
/// other than panes): Finder's meaning, the next or previous item by name,
/// whatever the sort. With nothing selected Tab takes the first name and
/// Shift+Tab the last; past either end it goes round.
public enum TabSelect {
    /// The id to select, nil when there are no items.
    public static func target(items: [(id: String, name: String)], selected: Set<String>, backwards: Bool) -> String? {
        let ordered = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !ordered.isEmpty else { return nil }
        let chosen = ordered.indices.filter { selected.contains(ordered[$0].id) }
        guard let first = chosen.first, let last = chosen.last else {
            return backwards ? ordered[ordered.count - 1].id : ordered[0].id
        }
        let index = backwards ? (first - 1 + ordered.count) % ordered.count : (last + 1) % ordered.count
        return ordered[index].id
    }
}

/// Which folders of a listing get a size measured (Finder's "Calculate all
/// sizes", kept light): those on screen, or every folder listed when the list
/// is sorted by size, since the order needs them. Before the list has said
/// what is on screen, the first screenful.
public enum SizeScope {
    public static let firstScreen = 60

    public static func folders(_ items: [FileItem], visible: Set<String>, sortedBySize: Bool) -> [URL] {
        let folders = items.filter { $0.isFolder && !$0.isInArchive }
        if sortedBySize { return folders.map(\.url) }
        if visible.isEmpty { return folders.prefix(firstScreen).map(\.url) }
        return folders.filter { visible.contains($0.id) }.map(\.url)
    }
}
