import Foundation

/// The list view's columns. Name always shows; the others can be chosen, and a
/// saved search keeps its own set. Path shows where an item is, below the flat
/// view's folder or, in search results, its folder.
public enum ListColumn: String, Codable, CaseIterable, Sendable {
    case name, path, modified, created, added, size, kind

    /// Finder's list view.
    public static let standard: [ListColumn] = [.name, .modified, .size, .kind]

    public var title: String {
        switch self {
        case .name: return "Name"
        case .path: return "Where"
        case .modified: return "Date Modified"
        case .created: return "Date Created"
        case .added: return "Date Added"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }

    /// The sort a click on the header asks for; Where sorts by name.
    public var sortField: SortField {
        switch self {
        case .name, .path: return .name
        case .modified: return .modified
        case .created: return .created
        case .added: return .added
        case .size: return .size
        case .kind: return .kind
        }
    }

    /// Columns as shown: Name first, each once, and Where added in flat view.
    public static func shown(_ chosen: [ListColumn]?, flat: Bool) -> [ListColumn] {
        var columns: [ListColumn] = [.name]
        for column in chosen ?? standard where !columns.contains(column) { columns.append(column) }
        if flat, !columns.contains(.path) { columns.insert(.path, at: 1) }
        return columns
    }

    /// "name,modified,size": the saved-search file's form.
    public static func text(_ columns: [ListColumn]) -> String {
        columns.map(\.rawValue).joined(separator: ",")
    }

    /// Unknown names are left out; nil when nothing known is left.
    public static func parse(_ text: String) -> [ListColumn]? {
        let columns = text.split(separator: ",").compactMap { ListColumn(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        return columns.isEmpty ? nil : columns
    }
}
