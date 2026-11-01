import Foundation

/// The sections of the result list, in the order they are shown: the top
/// hit, then what Return runs on the Mac (answers, apps, settings, commands,
/// windows), then files, then bookmarks and other text, then the web, with the
/// rows offered when nothing matches last.
///
/// The raw values are saved with recents and favourites, so each keeps the
/// number it was given; the order of the cases is the display order.
public enum ResultSection: Int, Codable, CaseIterable, Comparable, Sendable {
    case favourites = 0
    case recents = 1
    case topHit = 2
    case answers = 3
    case apps = 4
    case system = 7
    case grandLine = 5
    case windows = 6
    case files = 11
    case bookmarks = 8
    case snippets = 9
    case symbols = 10
    case web = 12
    /// Offered when nothing matches: create a file, run in Terminal, calculate.
    case otherActions = 13

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

    /// The default display order (the order of the cases), not the raw values.
    public static func < (lhs: ResultSection, rhs: ResultSection) -> Bool {
        position(lhs) < position(rhs)
    }

    private static func position(_ section: ResultSection) -> Int {
        allCases.firstIndex(of: section) ?? section.rawValue
    }
}
