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
    ///   - libraryNames: no longer used: ~/Library is a rule, whatever it holds.
    public static func exclusions(home: String, libraryNames: [String]) -> IndexExclusions {
        IndexExclusions.home(home, libraryNames: libraryNames)
    }

    /// The rules for a home folder, by its real path.
    public static func exclusions(home: String, fileManager: FileManager = .default) -> IndexExclusions {
        IndexExclusions.home(home)
    }
}
