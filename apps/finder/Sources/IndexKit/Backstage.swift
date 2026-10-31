import Foundation

/// The places on a Mac that hold app data rather than a person's files:
/// ~/Library (except ~/Library/CloudStorage, where Google Drive keeps its files),
/// the system folders, the insides of packages (.app and the like), the folders
/// IndexKit skips by name (.git, node_modules, caches, the Trash) and, when asked,
/// hidden folders. Searches use it to drop results a person rarely means.
public enum Backstage {
    /// Top-level folders that belong to macOS rather than a person.
    public static let systemFolders: Set<String> = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/opt", "/cores"]

    /// Whether `path` is backstage.
    /// - Parameters:
    ///   - home: the home folder.
    ///   - scope: the folder the search was limited to. Only the part of the path
    ///     below it counts, so a search scoped inside such a place keeps its results.
    ///   - hidden: also count names starting with a dot.
    public static func contains(
        _ path: String,
        home: String,
        scope: String? = nil,
        exclusions: IndexExclusions = .standard,
        hidden: Bool = false
    ) -> Bool {
        let base = scope.flatMap { isInside(path, $0) ? trimmed($0) : nil } ?? "/"
        let library = trimmed(home) + "/Library"
        if isInside(path, library), path != library, !isInside(path, library + "/CloudStorage"), !isInside(base, library) {
            return true
        }
        if base == "/", systemFolders.contains(where: { isInside(path, $0) }) { return true }
        let rest = base == "/" ? Substring(path) : path.dropFirst(base.count)
        let names = rest.split(separator: "/")
        for (i, name) in names.enumerated() {
            let name = String(name)
            if exclusions.skips(name) { return true }
            if hidden, name.hasPrefix(".") { return true }
            if i < names.count - 1, exclusions.isPackage(name) { return true }
        }
        return false
    }

    /// Whether `path` is `folder` or below it.
    public static func isInside(_ path: String, _ folder: String) -> Bool {
        let folder = trimmed(folder)
        if folder == "/" { return path.hasPrefix("/") }
        return path == folder || path.hasPrefix(folder + "/")
    }

    static func trimmed(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
