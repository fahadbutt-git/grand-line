import Foundation

/// A first character that sends the query to one provider.
public enum Prefix: String, CaseIterable, Codable, Sendable {
    case files = "."
    case calculator = "="
    case web = "?"
    case bookmarks = "%"
    case windows = "<"
    case reminder = "!"
    case shell = ">"
    case snippets = ";"
    case clipboard = "$"
    case symbols = ":"
    case providers = "/"
    case exact = "'"
    case saved = "@"

    public var title: String {
        switch self {
        case .files: return "Files and their contents"
        case .calculator: return "Calculator, units, currency, dates and time zones"
        case .web: return "Search the web"
        case .bookmarks: return "Bookmarks"
        case .windows: return "Open windows"
        case .reminder: return "New reminder"
        case .shell: return "Run a shell command"
        case .snippets: return "Espanso snippets"
        case .clipboard: return "Clipboard history"
        case .symbols: return "Emoji and science symbols"
        case .providers: return "List of prefixes"
        case .exact: return "Exact match only"
        case .saved: return "Saved searches"
        }
    }

    public var symbol: String {
        switch self {
        case .files: return "doc.text.magnifyingglass"
        case .calculator: return "equal.square"
        case .web: return "globe"
        case .bookmarks: return "bookmark"
        case .windows: return "macwindow.on.rectangle"
        case .reminder: return "bell"
        case .shell: return "terminal"
        case .snippets: return "text.quote"
        case .clipboard: return "list.clipboard"
        case .symbols: return "character"
        case .providers: return "list.bullet"
        case .exact: return "quote.opening"
        case .saved: return "magnifyingglass.circle"
        }
    }
}
