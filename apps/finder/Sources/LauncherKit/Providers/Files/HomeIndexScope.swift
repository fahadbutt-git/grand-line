import Foundation
import IndexKit

/// What the name index of the home folder leaves out: IndexKit's standard
/// exclusions (.git, node_modules, .build, caches, the Trash) and everything in
/// ~/Library except ~/Library/CloudStorage, where Google Drive keeps its files.
public enum HomeIndexScope {
    /// The same rules the Grand Line Index service uses (`IndexExclusions.home`).
    public static let kept: Set<String> = IndexExclusions.keptInLibrary

    /// - Parameters:
    ///   - home: the home folder as the index sees it (a real path).
    ///   - libraryNames: the names in ~/Library.
    public static func exclusions(home: String, libraryNames: [String]) -> IndexExclusions {
        IndexExclusions.home(home, libraryNames: libraryNames)
    }

    /// Reads ~/Library once; call it off the main thread.
    public static func exclusions(home: String, fileManager: FileManager = .default) -> IndexExclusions {
        let real = FolderWatcher.realPath(home)
        let names = (try? fileManager.contentsOfDirectory(atPath: real + "/Library")) ?? []
        return exclusions(home: real, libraryNames: names)
    }
}
