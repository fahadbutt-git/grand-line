import Foundation

/// `@name`: Nexus's saved searches (~/.config/grand-line/nexus/saved-searches.tsv,
/// name TAB query). Return runs one as a `.` search.
public final class SavedSearchProvider: InstantProvider, @unchecked Sendable {
    public let id = "saved"
    public let title = "Saved searches"
    public let symbol = "magnifyingglass.circle"
    public let prefix: Prefix? = .saved
    public let inGlobalSearch = false
    let file: String
    private let lock = NSLock()
    private var entries: [(name: String, query: String)] = []

    public init(file: String = GrandLinePaths().savedSearches) {
        self.file = file
    }

    public static func parse(_ text: String) -> [(name: String, query: String)] {
        var entries: [(name: String, query: String)] = []
        for row in TSV.rows(text) where row.count >= 2 && !row[0].isEmpty && !row[1].isEmpty {
            let name = row[0].hasPrefix("@") ? String(row[0].dropFirst()) : row[0]
            entries.removeAll { $0.name.lowercased() == name.lowercased() }
            entries.append((name, row[1]))
        }
        return entries
    }

    public func reload() {
        let text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        let parsed = Self.parse(text)
        lock.withLock { entries = parsed }
    }

    /// For QueryKit's `@name` expansion.
    public func query(named name: String) -> String? {
        lock.withLock { entries.first { $0.name.lowercased() == name.lowercased() }?.query }
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let list = lock.withLock { entries }
        let rows = list.map { entry in
            LaunchResult(
                id: "saved:" + entry.name,
                title: entry.name,
                subtitle: entry.query,
                icon: .symbol("magnifyingglass.circle"),
                section: .files,
                accessory: "@" + entry.name,
                actions: [LaunchAction.complete(". @" + entry.name, title: "Search")],
                providerID: id
            )
        }
        return query.term.isEmpty ? rows : Catalog(rows).search(query.term)
    }
}
