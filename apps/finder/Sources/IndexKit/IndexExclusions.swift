import Foundation

/// What the index leaves out.
public struct IndexExclusions: Sendable, Equatable {
    /// Files and folders with these exact names are skipped, with everything inside.
    public var names: Set<String>
    /// Names starting with any of these are skipped.
    public var prefixes: [String]
    /// Folders with these extensions (app bundles and the like) are indexed as one
    /// item, without their contents.
    public var packageExtensions: Set<String>
    /// Absolute folders skipped with everything inside.
    public var paths: Set<String>

    public init(
        names: Set<String> = [],
        prefixes: [String] = [],
        packageExtensions: Set<String> = [],
        paths: Set<String> = []
    ) {
        self.names = names
        self.prefixes = prefixes
        self.packageExtensions = packageExtensions
        self.paths = paths
    }

    public static let standard = IndexExclusions(
        names: [
            ".DS_Store", ".localized", ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm",
            "DerivedData", "__pycache__", ".cache", "Caches", ".Trash", ".Trashes",
            ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems",
        ],
        prefixes: ["._"],
        packageExtensions: [
            "app", "appex", "bundle", "framework", "plugin", "kext", "xpc",
            "photoslibrary", "musiclibrary", "tvlibrary",
        ]
    )

    public static let none = IndexExclusions()

    public func skips(_ name: String) -> Bool {
        names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }

    public func skips(path: String) -> Bool {
        paths.contains(path)
    }

    public func isPackage(_ name: String) -> Bool {
        guard !packageExtensions.isEmpty, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...]
        return packageExtensions.contains(String(ext)) || packageExtensions.contains(ext.lowercased())
    }
}
