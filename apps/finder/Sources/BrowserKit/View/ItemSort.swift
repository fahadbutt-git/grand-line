import Foundation

public enum SortField: String, Codable, CaseIterable, Sendable {
    case name
    case kind
    case size
    case modified
    case created
    /// Spotlight's last-used date (kMDItemLastUsedDate), read by `LastOpened`.
    case lastOpened
    /// When the item arrived in its folder.
    case added
    /// By first tag name; untagged items last.
    case tags
    /// The order you dragged items into (R7), kept per folder.
    case manual

    public var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .size: return "Size"
        case .modified: return "Date Modified"
        case .created: return "Date Created"
        case .lastOpened: return "Date Last Opened"
        case .added: return "Date Added"
        case .tags: return "Tags"
        case .manual: return "Manual"
        }
    }

    /// Dates and sizes start newest and largest, like Finder.
    public var defaultAscending: Bool {
        switch self {
        case .name, .kind, .manual, .tags: return true
        case .size, .modified, .created, .lastOpened, .added: return false
        }
    }
}

public struct ItemSort: Codable, Hashable, Sendable {
    public var field: SortField
    public var ascending: Bool
    public var foldersFirst: Bool

    public init(field: SortField = .name, ascending: Bool? = nil, foldersFirst: Bool = true) {
        self.field = field
        self.ascending = ascending ?? field.defaultAscending
        self.foldersFirst = foldersFirst
    }

    /// Clicking a column header: the same column flips, another starts at its default.
    public func clicking(_ field: SortField) -> ItemSort {
        if field == self.field { return ItemSort(field: field, ascending: !ascending, foldersFirst: foldersFirst) }
        return ItemSort(field: field, foldersFirst: foldersFirst)
    }
}

/// Sorts rows. Folder sizes come from FileKit's FolderSize and last-opened
/// dates from `LastOpened`, both keyed by path.
public enum ItemSorter {
    public static func sorted(
        _ items: [FileItem], by sort: ItemSort, folderSizes: [String: Int64] = [:],
        lastOpened: [String: Date] = [:], manual: [String] = []
    ) -> [FileItem] {
        if sort.field == .manual { return ManualOrder.apply(manual, to: items) }
        let names = items.map { $0.name as NSString }
        let order = items.indices.sorted { a, b in
            let x = items[a], y = items[b]
            if sort.foldersFirst, x.isFolder != y.isFolder { return x.isFolder }
            let result = compare(x, y, names[a], names[b], sort.field, folderSizes, lastOpened)
            if result == .orderedSame { return names[a].localizedStandardCompare(names[b] as String) == .orderedAscending }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return order.map { items[$0] }
    }

    static func compare(
        _ x: FileItem, _ y: FileItem, _ xName: NSString, _ yName: NSString,
        _ field: SortField, _ sizes: [String: Int64], _ opened: [String: Date]
    ) -> ComparisonResult {
        switch field {
        case .name, .manual:
            return xName.localizedStandardCompare(yName as String)
        case .kind:
            return x.kind.localizedStandardCompare(y.kind)
        case .size:
            return order(x.size ?? sizes[x.path] ?? -1, y.size ?? sizes[y.path] ?? -1)
        case .modified:
            return order(x.modified ?? .distantPast, y.modified ?? .distantPast)
        case .created:
            return order(x.created ?? .distantPast, y.created ?? .distantPast)
        case .lastOpened:
            return order(opened[x.path] ?? .distantPast, opened[y.path] ?? .distantPast)
        case .added:
            return order(x.added ?? .distantPast, y.added ?? .distantPast)
        case .tags:
            switch (x.tags.first, y.tags.first) {
            case let (a?, b?): return a.localizedStandardCompare(b)
            case (.some, nil): return .orderedAscending
            case (nil, .some): return .orderedDescending
            case (nil, nil): return .orderedSame
            }
        }
    }

    static func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
