import Foundation

/// One saved search (R18): the query and how its results show, stored
/// together (Everything's bookmarks): where it looks, the list's columns, the
/// sort and the grouping. A part left empty uses the window's own.
public struct SavedSearch: Equatable, Sendable {
    public var name: String
    public var query: String
    public var scope: SearchScope?
    public var columns: [ListColumn]?
    /// The sort, with Keep Folders on Top and Group By in it.
    public var sort: ItemSort?

    public init(name: String, query: String, scope: SearchScope? = nil, columns: [ListColumn]? = nil, sort: ItemSort? = nil) {
        self.name = name
        self.query = query
        self.scope = scope
        self.columns = columns
        self.sort = sort
    }

    /// Where it searches when run: its own scope, else the home folder.
    public var runScope: SearchScope { scope ?? .home }
}

/// Saved searches, shown as smart folders in the sidebar and usable as
/// `@name` in any query. One per line in ~/.config/grand-line/nexus/saved-searches.tsv:
///
///     name TAB query TAB scope TAB columns TAB sort TAB group
///
/// scope is `home`, `drive`, `mac` or `folder:/path`; columns a list such as
/// `name,modified,size`; sort `modified:desc`, with `+folders` for Keep
/// Folders on Top; group `kind` or `none`. Empty fields use the window's own.
/// Lines starting with # are comments. Sight reads the first two fields only.
/// Files from before scope and columns were stored hold only name and query;
/// they load with the home folder as scope (where they always ran) and are
/// written back in the new form (`isLegacy`).
public struct SavedSearches: Equatable, Sendable {
    public private(set) var searches: [SavedSearch]
    /// Read from a file in the old two-field form, so it should be written again.
    public private(set) var isLegacy = false

    public static let header = "# name\tquery\tscope\tcolumns\tsort\tgroup"

    public init(searches: [SavedSearch] = []) {
        self.searches = searches
    }

    public init(entries: [(name: String, query: String)]) {
        self.searches = entries.map { SavedSearch(name: $0.name, query: $0.query) }
    }

    /// Name and query pairs, as files before scopes had them.
    public var entries: [(name: String, query: String)] { searches.map { (name: $0.name, query: $0.query) } }

    public static func == (a: SavedSearches, b: SavedSearches) -> Bool {
        a.searches == b.searches
    }

    public static func parse(_ text: String) -> SavedSearches {
        var searches: [SavedSearch] = []
        var sawHeader = false
        var sawOldLine = false
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == header { sawHeader = true }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            if fields.count == 2 { sawOldLine = true }
            let name = fields[0].hasPrefix("@") ? String(fields[0].dropFirst()) : fields[0]
            var search = SavedSearch(name: name, query: fields[1])
            search.scope = fields.count > 2 ? parseScope(fields[2]) : nil
            search.columns = fields.count > 3 ? ListColumn.parse(fields[3]) : nil
            search.sort = parseSort(fields.count > 4 ? fields[4] : "", group: fields.count > 5 ? fields[5] : "")
            searches.removeAll { $0.name.lowercased() == name.lowercased() }
            searches.append(search)
        }
        var saved = SavedSearches(searches: searches)
        if !searches.isEmpty, !sawHeader || sawOldLine {
            saved.isLegacy = true
            // Old searches always ran from the home folder.
            for index in saved.searches.indices where saved.searches[index].scope == nil {
                saved.searches[index].scope = .home
            }
        }
        return saved
    }

    public static func load(_ url: URL) -> SavedSearches {
        guard let data = try? Data(contentsOf: url) else { return SavedSearches() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    public var names: [String] { searches.map(\.name) }

    public func search(named name: String) -> SavedSearch? {
        searches.first { $0.name.lowercased() == name.lowercased() }
    }

    /// For QueryKit's `@name` expansion; names ignore case.
    public func query(named name: String) -> String? {
        search(named: name)?.query
    }

    public mutating func save(_ name: String, query: String) {
        save(SavedSearch(name: name, query: query))
    }

    /// Adds a search, or replaces the one of the same name (ignoring case).
    public mutating func save(_ search: SavedSearch) {
        var search = search
        search.name = search.name.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces)
        search.query = search.query.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        guard !search.name.isEmpty else { return }
        searches.removeAll { $0.name.lowercased() == search.name.lowercased() }
        searches.append(search)
    }

    public mutating func remove(_ name: String) {
        searches.removeAll { $0.name.lowercased() == name.lowercased() }
    }

    public func text() -> String {
        Self.header + "\n" + searches.map { search in
            let sort = search.sort
            let fields = [
                search.name, search.query, search.scope.map(Self.scopeText) ?? "",
                search.columns.map(ListColumn.text) ?? "", sort.map(Self.sortText) ?? "",
                sort.map { $0.grouping.rawValue } ?? "",
            ]
            return fields.joined(separator: "\t") + "\n"
        }.joined()
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text().utf8).write(to: url, options: .atomic)
    }

    // MARK: Fields

    static func scopeText(_ scope: SearchScope) -> String {
        switch scope {
        case .folder(let path): return "folder:" + path
        case .home: return "home"
        case .drive: return "drive"
        case .mac: return "mac"
        }
    }

    static func parseScope(_ text: String) -> SearchScope? {
        switch text.lowercased() {
        case "": return nil
        case "home": return .home
        case "drive": return .drive
        case "mac": return .mac
        default:
            guard text.lowercased().hasPrefix("folder:") else { return nil }
            let path = String(text.dropFirst("folder:".count))
            return path.hasPrefix("/") ? .folder(path) : nil
        }
    }

    static func sortText(_ sort: ItemSort) -> String {
        sort.field.rawValue + ":" + (sort.ascending ? "asc" : "desc") + (sort.foldersFirst ? "+folders" : "")
    }

    /// nil when neither a sort nor a grouping is stored.
    static func parseSort(_ text: String, group: String) -> ItemSort? {
        let grouping = ItemGrouping(rawValue: group.lowercased())
        let parts = text.lowercased().split(separator: "+").map(String.init)
        let order = parts.first?.split(separator: ":").map(String.init) ?? []
        guard let fieldName = order.first, let field = SortField.allCases.first(where: { $0.rawValue.lowercased() == fieldName }) else {
            guard let grouping, grouping != .none else { return nil }
            return ItemSort(grouping: grouping)
        }
        let ascending = order.count > 1 ? order[1] != "desc" : nil
        return ItemSort(field: field, ascending: ascending, foldersFirst: parts.dropFirst().contains("folders"),
                        grouping: grouping ?? ItemGrouping.none)
    }
}
