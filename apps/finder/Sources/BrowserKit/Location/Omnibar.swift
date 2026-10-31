import Foundation

/// The path bar's field as one keyboard target (the Files v4 Omnibar): a path
/// with completion, a filter on the current folder, a search, or a command.
///
/// - `/`, `~`, `.`, `Drive/` or any text with a slash is a path (Tab completes).
/// - `?words` searches with the search field's scopes (Cmd+F still opens the field).
/// - `>words` runs a command from the catalog.
/// - Anything else filters the current folder as you type. When the field was
///   opened with Go to Folder (Shift+Cmd+G), a name is a folder to go to
///   instead, as in Finder.
public enum Omnibar {
    /// How the field was opened.
    public enum Origin: Equatable, Sendable {
        /// Shift+Cmd+G: Finder's Go to Folder.
        case goToFolder
        /// Option+Cmd+G or a click on the path bar: filter first.
        case filter
    }

    public enum Mode: Equatable, Sendable {
        case path(String)
        /// A folder name to find in the index (Go to Folder).
        case folderName(String)
        case filter(String)
        case search(String)
        case command(String)

        public var text: String {
            switch self {
            case .path(let text), .folderName(let text), .filter(let text), .search(let text), .command(let text): return text
            }
        }

        /// The label at the field's leading edge, so filtering and searching never look alike.
        public var badge: String {
            switch self {
            case .path, .folderName: return "Go"
            case .filter: return "Filter"
            case .search: return "Search"
            case .command: return "Command"
            }
        }

        public var symbol: String {
            switch self {
            case .path, .folderName: return "folder"
            case .filter: return "line.3.horizontal.decrease"
            case .search: return "magnifyingglass"
            case .command: return "chevron.right"
            }
        }

        /// The placeholder for an empty field.
        public static func placeholder(_ origin: Origin) -> String {
            switch origin {
            case .goToFolder: return "Path or folder name  ·  ?search  ·  >command"
            case .filter: return "Filter this folder  ·  path  ·  ?search  ·  >command"
            }
        }
    }

    public static let searchPrefix: Character = "?"
    public static let commandPrefix: Character = ">"

    public static func mode(for text: String, origin: Origin, aliases: [String: URL] = [:]) -> Mode {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.first == commandPrefix { return .command(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if trimmed.first == searchPrefix { return .search(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        if PathInput.looksLikePath(trimmed, aliases: aliases) { return .path(text) }
        switch origin {
        case .goToFolder: return .folderName(text)
        case .filter: return .filter(text)
        }
    }

    // MARK: Commands

    /// One row in the command list: "Sort By › Date Added  ⌃⌥⌘4".
    public struct CommandMatch: Equatable, Sendable {
        public let command: BrowserCommand
        public let title: String
        public let shortcut: String
    }

    /// Commands whose title (with its menu and submenu) matches the typed
    /// words, best first: a title that starts with them, then a word that does,
    /// then the letters in order. Empty text lists every command in menu order.
    public static func commands(
        matching text: String, limit: Int = 12, isAvailable: (BrowserCommand) -> Bool = { _ in true }
    ) -> [CommandMatch] {
        let query = fold(text)
        var scored: [(rank: Int, order: Int, match: CommandMatch)] = []
        for (order, spec) in CommandCatalog.all.enumerated() where isAvailable(spec.command) {
            let title = spec.submenu.map { "\($0) \u{203A} \(spec.title)" } ?? spec.title
            let shortcut = spec.shortcuts.first?.description ?? ""
            let match = CommandMatch(command: spec.command, title: title, shortcut: shortcut)
            guard let rank = rank(query, in: fold(title), menu: fold(spec.menu.rawValue)) else { continue }
            scored.append((rank, order, match))
        }
        var seen = Set<BrowserCommand>()
        return scored.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.match)
            .filter { seen.insert($0.command).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// Lower is better; nil when it does not match.
    static func rank(_ query: String, in title: String, menu: String) -> Int? {
        if query.isEmpty { return 0 }
        let plain = title.replacingOccurrences(of: "\u{2026}", with: "")
        if plain.hasPrefix(query) { return 0 }
        let words = plain.split(whereSeparator: { $0 == " " || $0 == "\u{203A}" }).map(String.init)
        let parts = query.split(separator: " ").map(String.init)
        if parts.allSatisfy({ part in words.contains { $0.hasPrefix(part) } }) { return 1 }
        if plain.contains(query) { return 2 }
        if (menu + " " + plain).contains(query) { return 3 }
        if isSubsequence(query.replacingOccurrences(of: " ", with: ""), of: plain) { return 4 }
        return nil
    }

    static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var rest = Substring(haystack)
        for character in needle {
            guard let found = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: found)...]
        }
        return true
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
