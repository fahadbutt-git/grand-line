import Foundation
import IndexKit

/// Flat view (Directory Opus): a folder and everything below it in one list,
/// with a path column. The names come from the shared index, scoped to the
/// folder, so it is instant for any subtree; folders the index leaves out (the
/// Trash, ~/Library, a node_modules) are read from disk instead. Either way
/// Backstage's exclusions apply below the folder: no .git, caches, package
/// insides or, unless hidden files show, dot folders.
public enum FlatListing {
    /// The most rows a flat view lists.
    public static let limit = 5_000

    /// The index answers name searches, not "everything", so the listing asks
    /// for every letter and digit and a few marks a name can hold, scoped to
    /// the folder, and joins the answers. Every name the index folds to ASCII
    /// holds at least one of them.
    public static let probes: [String] = "abcdefghijklmnopqrstuvwxyz0123456789".map { String($0) } + [".", "-", "_"]

    /// Whether the index can answer for `folder`, or it must be read from disk.
    public static func needsDisk(_ folder: String, home: String) -> Bool {
        SearchPlan.indexSkips(folder, home: home) || !Backstage.isInside(folder, home)
    }

    /// The index's answers joined: each path once, strictly below `folder`,
    /// without what Backstage leaves out, sorted by path, at most `limit`.
    public static func merge(_ batches: [[String]], under folder: String, home: String, showHidden: Bool, limit: Int = limit) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        let base = trimmed(folder)
        for batch in batches {
            for path in batch where seen.insert(path).inserted {
                guard path != base, Backstage.isInside(path, base) else { continue }
                if Backstage.contains(path, home: home, scope: base, hidden: !showHidden) { continue }
                paths.append(path)
            }
        }
        paths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return Array(paths.prefix(limit))
    }

    /// Whether a probe's answer may have been cut short, so the list is partial.
    public static func isPartial(_ batches: [[String]], probeLimit: Int) -> Bool {
        batches.contains { $0.count >= probeLimit }
    }

    /// Reads `folder` and everything below it from disk, skipping what
    /// Backstage leaves out and not going inside packages. Stops at `limit`.
    public static func walk(_ folder: URL, home: String, showHidden: Bool, limit: Int = limit) -> [String] {
        let base = trimmed(folder.path)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden { options.insert(.skipsHiddenFiles) }
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: options) else { return [] }
        var paths: [String] = []
        while let next = walker.nextObject() as? URL {
            let path = next.path
            if Backstage.contains(path, home: home, scope: base, hidden: !showHidden) {
                let values = try? next.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { walker.skipDescendants() }
                continue
            }
            paths.append(path)
            if paths.count >= limit { break }
        }
        paths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return paths
    }

    /// The path column: the item's folder below the flat view's folder, "" for
    /// items directly in it ("Drafts/v2").
    public static func relativeFolder(of path: String, under folder: String) -> String {
        let base = trimmed(folder)
        let parent = (path as NSString).deletingLastPathComponent
        guard parent != base, Backstage.isInside(parent, base) else { return "" }
        return String(parent.dropFirst(base == "/" ? 1 : base.count + 1))
    }

    static func trimmed(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
