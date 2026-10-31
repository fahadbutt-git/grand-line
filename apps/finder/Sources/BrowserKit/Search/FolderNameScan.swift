import Foundation

/// Name matches read straight from disk, for a search in a folder the name
/// index leaves out (the Trash, a node_modules, ~/Library). Finder finds
/// "conj" in the Trash; without this the search there would always be empty.
public enum FolderNameScan {
    /// Paths below `folders` whose names hold every word (ignoring case and
    /// accents), in the order found. Reads at most `budget` entries, so a huge
    /// folder costs a bounded time, and skips hidden files and package insides.
    public static func paths(in folders: [String], words: [String], limit: Int = 400, budget: Int = 20_000) -> [String] {
        let words = words.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var found: [String] = []
        var read = 0
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: URL(fileURLWithPath: folder, isDirectory: true),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            while let url = walker.nextObject() as? URL {
                read += 1
                if read > budget || found.count >= limit { return found }
                if matches(url.lastPathComponent, words) { found.append(url.path) }
            }
        }
        return found
    }

    static func matches(_ name: String, _ words: [String]) -> Bool {
        words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
