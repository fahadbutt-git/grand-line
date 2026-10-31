import Foundation

/// A folder whose contents changed. `recursive` means everything below it may
/// have changed too (FSEvents dropped events or the folder itself moved).
public struct FolderChange: Sendable, Hashable {
    public let path: String
    public let recursive: Bool

    public init(path: String, recursive: Bool = false) {
        self.path = FolderChange.normalize(path)
        self.recursive = recursive
    }

    /// One change per folder, sorted by path. A recursive change absorbs every change below it.
    public static func coalesce(_ changes: [FolderChange]) -> [FolderChange] {
        var recursiveByPath: [String: Bool] = [:]
        for change in changes {
            recursiveByPath[change.path] = (recursiveByPath[change.path] ?? false) || change.recursive
        }
        let deep = recursiveByPath.compactMap { entry in entry.value ? entry.key : nil }
        var result: [FolderChange] = []
        for (path, recursive) in recursiveByPath {
            if deep.contains(where: { $0 != path && isInside(path, $0) }) { continue }
            result.append(FolderChange(path: path, recursive: recursive))
        }
        return result.sorted { $0.path < $1.path }
    }

    /// True when `path` is `folder` or below it.
    public static func isInside(_ path: String, _ folder: String) -> Bool {
        if path == folder || folder == "/" { return true }
        return path.hasPrefix(folder) && path.utf8.dropFirst(folder.utf8.count).first == UInt8(ascii: "/")
    }

    static func normalize(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
