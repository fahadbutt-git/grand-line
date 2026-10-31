import Foundation

/// What an empty pane says. A search with nothing in its scope says where it
/// looked and offers the whole Mac, as Finder does when a folder search comes
/// back empty ("No results in Trash." with "Search This Mac?").
public struct PaneEmptyState: Equatable, Sendable {
    public let message: String
    /// The scope the button widens to; nil when there is nothing wider.
    public let widen: SearchScope?

    public var widenTitle: String { "Search This Mac?" }

    /// - Parameter folderTitle: the name a folder scope's chip shows ("Trash"
    ///   for ~/.Trash); the folder's own name when nil.
    public static func make(for location: BrowserLocation, folderTitle: String? = nil) -> PaneEmptyState {
        switch location {
        case .search(_, let scope):
            switch scope {
            case .mac:
                return PaneEmptyState(message: "No matches", widen: nil)
            case .folder:
                return PaneEmptyState(message: "No results in \(folderTitle ?? scope.title).", widen: .mac)
            case .home, .drive:
                return PaneEmptyState(message: "No results in \(scope.title).", widen: .mac)
            }
        case .recents:
            return PaneEmptyState(message: "No recent files", widen: nil)
        case .folder, .archive:
            return PaneEmptyState(message: "Empty folder", widen: nil)
        }
    }
}
