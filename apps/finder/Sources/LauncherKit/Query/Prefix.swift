import Foundation

/// A first character that sends the query to one provider. The raw value is
/// the prefix's stable name; `triggers` are what you type, the first being the
/// one shown. The scope prefixes are `/` files, `=` maths, `:` clipboard, `>`
/// commands, `!` windows and `,` settings; the earlier ones (`.` files, `<`
/// windows) still work, and symbols moved to `::` when the clipboard has `:`.
public enum Prefix: String, CaseIterable, Codable, Sendable {
    case files = "."
    case calculator = "="
    case web = "?"
    case bookmarks = "%"
    case windows = "<"
    case shell = ">"
    case snippets = ";"
    case clipboard = "$"
    case clipboardHistory = ":"
    case symbols = "::"
    case settings = ","
    case providers = "/"
    case exact = "'"
    case saved = "@"

    /// What you type for it; the first is the one shown.
    public var triggers: [String] {
        switch self {
        case .files: return ["/", "."]
        case .windows: return ["!", "<"]
        case .symbols: return ["::", ":"]
        default: return [rawValue]
        }
    }

    /// The prefix as shown in lists and Settings.
    public var display: String { triggers[0] }

    /// What Return types to enter the prefix: "/ " for files, since "/" alone lists the prefixes.
    public var completion: String {
        self == .files ? "/ " : display
    }

    public var title: String {
        switch self {
        case .files: return "Files and their contents"
        case .calculator: return "Calculator, units, currency, dates and time zones"
        case .web: return "Search the web"
        case .bookmarks: return "Bookmarks"
        case .windows: return "Open windows"
        case .shell: return "Commands, scripts and the shell"
        case .snippets: return "Espanso snippets"
        case .clipboard: return "Show Maccy"
        case .clipboardHistory: return "Clipboard history"
        case .symbols: return "Emoji and science symbols"
        case .settings: return "Settings"
        case .providers: return "List of prefixes"
        case .exact: return "Exact match only"
        case .saved: return "Saved searches"
        }
    }

    /// The short name in the hint chip at the start of the field.
    public var chip: String {
        switch self {
        case .files: return "Files"
        case .calculator: return "Maths"
        case .web: return "Web"
        case .bookmarks: return "Bookmarks"
        case .windows: return "Windows"
        case .shell: return "Commands"
        case .snippets: return "Snippets"
        case .clipboard: return "Maccy"
        case .clipboardHistory: return "Clipboard"
        case .symbols: return "Symbols"
        case .settings: return "Settings"
        case .providers: return "Prefixes"
        case .exact: return "Exact"
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
        case .shell: return "terminal"
        case .snippets: return "text.quote"
        case .clipboard: return "list.clipboard"
        case .clipboardHistory: return "doc.on.clipboard"
        case .symbols: return "character"
        case .settings: return "gearshape"
        case .providers: return "list.bullet"
        case .exact: return "quote.opening"
        case .saved: return "magnifyingglass.circle"
        }
    }
}
