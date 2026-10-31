import Foundation

/// Alfred's file buffer: Command+B adds the selected file row (or takes it out
/// again), the buffer shows as a row of chips under the field, and Command+K
/// then acts on every file in it. It empties after an action runs on it.
public struct FileBuffer: Sendable, Equatable {
    public private(set) var paths: [String] = []
    public static let limit = 200

    public init(paths: [String] = []) {
        for path in paths { add(path) }
    }

    public var isEmpty: Bool { paths.isEmpty }
    public var count: Int { paths.count }

    /// The file a row stands for, if it is a file or folder row.
    public static func path(of result: LaunchResult) -> String? {
        switch ResultKind.of(result) {
        case .file(let path, _): return path
        default: return nil
        }
    }

    public func contains(_ path: String) -> Bool { paths.contains(path) }

    @discardableResult
    public mutating func add(_ path: String) -> Bool {
        guard !path.isEmpty, !paths.contains(path), paths.count < Self.limit else { return false }
        paths.append(path)
        return true
    }

    public mutating func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    /// Adds the row's file, or takes it out when it is already in. Returns
    /// false for rows that are not files.
    @discardableResult
    public mutating func toggle(_ result: LaunchResult) -> Bool {
        guard let path = Self.path(of: result) else { return false }
        if contains(path) { remove(path) } else { add(path) }
        return true
    }

    /// Adds every path, or, when all of them are in already, takes them out.
    public mutating func toggle(paths more: [String]) {
        if !more.isEmpty, more.allSatisfy(contains) {
            for path in more { remove(path) }
        } else {
            for path in more { add(path) }
        }
    }

    public mutating func clear() { paths = [] }

    /// A chip under the field: the file's name, with its path for the tooltip.
    public struct Chip: Sendable, Hashable, Identifiable {
        public let name: String
        public let path: String
        public var id: String { path }
    }

    public var chips: [Chip] {
        paths.map { Chip(name: ($0 as NSString).lastPathComponent, path: $0) }
    }

    /// What Command+K lists while the buffer holds files.
    public var actions: [LaunchAction] { ActionPanel.fileActions(paths, inBuffer: true) }

    public var title: String {
        paths.count == 1 ? "1 file in the buffer" : "\(paths.count) files in the buffer"
    }
}
