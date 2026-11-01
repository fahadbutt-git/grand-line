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
    /// Folders of which only the named children are kept: every other child,
    /// whenever it was made, is skipped with everything inside. A rule, not a
    /// list read once: ~/Library keeps only CloudStorage, including against a
    /// folder an app creates there next week.
    public var keptOnly: [String: Set<String>]

    public init(
        names: Set<String> = [],
        prefixes: [String] = [],
        packageExtensions: Set<String> = [],
        paths: Set<String> = [],
        keptOnly: [String: Set<String>] = [:]
    ) {
        self.names = names
        self.prefixes = prefixes
        self.packageExtensions = packageExtensions
        self.paths = paths
        self.keptOnly = keptOnly
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

    /// ~/Library names the home index keeps: Google Drive and other cloud
    /// folders live in ~/Library/CloudStorage.
    public static let keptInLibrary: Set<String> = ["CloudStorage"]

    /// What the shared index of a home folder leaves out: the standard
    /// exclusions and everything in ~/Library except ~/Library/CloudStorage,
    /// as a rule on ~/Library (see `keptOnly`).
    /// - Parameters:
    ///   - home: the home folder as the index sees it (a real path).
    ///   - libraryNames: no longer used: the rule covers whatever is in ~/Library.
    public static func home(_ home: String, libraryNames: [String]) -> IndexExclusions {
        var rules = IndexExclusions.standard
        rules.keptOnly[home + "/Library"] = keptInLibrary
        return rules
    }

    /// The rules for a home folder, by its real path. Reads nothing from ~/Library.
    public static func home(_ home: String) -> IndexExclusions {
        Self.home(FolderWatcher.realPath(home), libraryNames: [])
    }

    public func skips(_ name: String) -> Bool {
        names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }

    /// Whether there are rules by path at all (a walk checks every child against them).
    public var hasPathRules: Bool { !paths.isEmpty || !keptOnly.isEmpty }

    /// Whether this exact path is left out by a path rule: an excluded path,
    /// or a child of a `keptOnly` folder that is not kept.
    public func skips(path: String) -> Bool {
        if paths.contains(path) { return true }
        guard !keptOnly.isEmpty, let slash = path.lastIndex(of: "/") else { return false }
        let parent = slash == path.startIndex ? "/" : String(path[..<slash])
        guard let kept = keptOnly[parent] else { return false }
        return !kept.contains(String(path[path.index(after: slash)...]))
    }

    /// Whether the path or anything above it is left out by a path rule.
    public func excludes(_ path: String) -> Bool {
        if paths.contains(where: { FolderChange.isInside(path, $0) }) { return true }
        for (parent, kept) in keptOnly {
            let prefix = parent.hasSuffix("/") ? parent : parent + "/"
            guard path.hasPrefix(prefix) else { continue }
            let rest = path.dropFirst(prefix.count)
            let child = rest.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            if !child.isEmpty, !kept.contains(child) { return true }
        }
        return false
    }

    public func isPackage(_ name: String) -> Bool {
        guard !packageExtensions.isEmpty, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...]
        return packageExtensions.contains(String(ext)) || packageExtensions.contains(ext.lowercased())
    }
}
