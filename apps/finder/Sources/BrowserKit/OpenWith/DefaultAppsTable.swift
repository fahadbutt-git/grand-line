import Foundation

/// ~/.grand-line/config/grand-line/default-apps.tsv (R34): app name TAB
/// extensions (".docx .doc") TAB fallback app. Open With lists these apps first.
public struct DefaultAppsTable: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let app: String
        public let extensions: [String]
        public let fallback: String?
    }

    public let rows: [Row]

    public init(rows: [Row] = []) {
        self.rows = rows
    }

    public static func parse(_ text: String) -> DefaultAppsTable {
        var rows: [Row] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2, !fields[0].isEmpty else { continue }
            let extensions = fields[1].split(separator: " ").map { normalize(String($0)) }.filter { !$0.isEmpty }
            let fallback = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
            rows.append(Row(app: fields[0], extensions: extensions, fallback: fallback))
        }
        return DefaultAppsTable(rows: rows)
    }

    public static func load(_ url: URL) -> DefaultAppsTable {
        guard let data = try? Data(contentsOf: url) else { return DefaultAppsTable() }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The table's apps for an extension, preferred first, then its fallback.
    public func apps(for ext: String) -> [String] {
        let wanted = Self.normalize(ext)
        var names: [String] = []
        for row in rows where row.extensions.contains(wanted) {
            for name in [row.app] + (row.fallback.map { [$0] } ?? []) where !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    static func normalize(_ ext: String) -> String {
        var text = ext.trimmingCharacters(in: .whitespaces).lowercased()
        while text.hasPrefix(".") { text.removeFirst() }
        return text
    }
}
