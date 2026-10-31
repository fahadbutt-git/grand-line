import Foundation

/// The sections of the result list, in the order they are shown.
public enum ResultSection: Int, Codable, CaseIterable, Comparable, Sendable {
    case favourites
    case recents
    case topHit
    case answers
    case apps
    case grandLine
    case windows
    case system
    case bookmarks
    case snippets
    case symbols
    case files
    case web
    /// Offered when nothing matches: create a file, run in Terminal, calculate.
    case otherActions

    public var title: String {
        switch self {
        case .favourites: return "Favourites"
        case .recents: return "Recent"
        case .topHit: return "Top hit"
        case .answers: return "Answers"
        case .apps: return "Apps"
        case .grandLine: return "Grand Line"
        case .windows: return "Windows"
        case .system: return "System"
        case .bookmarks: return "Bookmarks"
        case .snippets: return "Snippets"
        case .symbols: return "Symbols"
        case .files: return "Files"
        case .web: return "Web"
        case .otherActions: return "Other actions"
        }
    }

    /// Rows shown in this section when every provider runs. A prefix shows more.
    public var limit: Int {
        switch self {
        case .topHit: return 1
        case .answers, .otherActions: return 3
        case .symbols: return 10
        case .files, .web: return 8
        case .favourites, .recents: return 9
        default: return 6
        }
    }

    public static func < (lhs: ResultSection, rhs: ResultSection) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
