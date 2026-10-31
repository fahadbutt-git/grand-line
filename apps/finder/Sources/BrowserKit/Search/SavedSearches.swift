import Foundation

/// Saved searches (R18), shown as smart folders in the sidebar and usable as
/// `@name` in any query. One per line in ~/.config/grand-line/nexus/saved-searches.tsv:
/// name TAB query. Lines starting with # are comments.
public struct SavedSearches: Equatable, Sendable {
    public private(set) var entries: [(name: String, query: String)]

    public init(entries: [(name: String, query: String)] = []) {
        self.entries = entries
    }

    public static func == (a: SavedSearches, b: SavedSearches) -> Bool {
        a.entries.map(\.name) == b.entries.map(\.name) && a.entries.map(\.query) == b.entries.map(\.query)
    }

    public static func parse(_ text: String) -> SavedSearches {
        var entries: [(name: String, query: String)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let name = fields[0].hasPrefix("@") ? String(fields[0].dropFirst()) : fields[0]
            entries.removeAll { $0.name.lowercased() == name.lowercased() }
            entries.append((name: name, query: fields[1]))
        }
        return SavedSearches(entries: entries)
    }

    public static func load(_ url: URL) -> SavedSearches {
        guard let data = try? Data(contentsOf: url) else { return SavedSearches() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    public var names: [String] { entries.map(\.name) }

    /// For QueryKit's `@name` expansion; names ignore case.
    public func query(named name: String) -> String? {
        entries.first { $0.name.lowercased() == name.lowercased() }?.query
    }

    public mutating func save(_ name: String, query: String) {
        let clean = name.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        entries.removeAll { $0.name.lowercased() == clean.lowercased() }
        entries.append((name: clean, query: query.replacingOccurrences(of: "\n", with: " ")))
    }

    public mutating func remove(_ name: String) {
        entries.removeAll { $0.name.lowercased() == name.lowercased() }
    }

    public func text() -> String {
        "# name\tquery\n" + entries.map { $0.name + "\t" + $0.query + "\n" }.joined()
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text().utf8).write(to: url, options: .atomic)
    }
}
