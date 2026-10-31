import Foundation
import IndexKit

/// What the name index of the home folder leaves out: IndexKit's standard
/// exclusions (.git, node_modules, .build, caches, the Trash) and everything in
/// ~/Library except ~/Library/CloudStorage, where Google Drive keeps its files.
public enum HomeIndexScope {
    public static let kept: Set<String> = ["CloudStorage"]

    /// - Parameters:
    ///   - home: the home folder as the index sees it (a real path).
    ///   - libraryNames: the names in ~/Library.
    public static func exclusions(home: String, libraryNames: [String]) -> IndexExclusions {
        var rules = IndexExclusions.standard
        let library = home + "/Library"
        for name in libraryNames where !kept.contains(name) {
            rules.paths.insert(library + "/" + name)
        }
        return rules
    }

    /// Reads ~/Library once; call it off the main thread.
    public static func exclusions(home: String, fileManager: FileManager = .default) -> IndexExclusions {
        let real = FolderWatcher.realPath(home)
        let names = (try? fileManager.contentsOfDirectory(atPath: real + "/Library")) ?? []
        return exclusions(home: real, libraryNames: names)
    }
}
