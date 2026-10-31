import Foundation
import SQLite3

/// Zen's bookmarks (Firefox's format), from each profile's places.sqlite.
/// The database is copied first, because Zen keeps it locked while it runs.
public enum ZenBookmarks {
    /// One row of moz_bookmarks joined with moz_places. Type 1 is a bookmark, 2 a folder.
    public struct Row: Sendable, Equatable {
        public let id: Int
        public let parent: Int
        public let type: Int
        public let title: String
        public let url: String?

        public init(id: Int, parent: Int, type: Int, title: String, url: String?) {
            self.id = id
            self.parent = parent
            self.type = type
            self.title = title
            self.url = url
        }
    }

    /// Firefox's built-in folders, by their stored names.
    static let rootNames = ["toolbar": "Bookmarks toolbar", "menu": "Bookmarks menu", "unfiled": "Other bookmarks", "mobile": "Mobile bookmarks"]

    /// Bookmarks with their folder trail ("Bookmarks toolbar › Research").
    public static func bookmarks(from rows: [Row]) -> [Bookmark] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Walk up to the root, whose parent is 0, at most 64 folders deep.
        func trail(_ parent: Int) -> [String] {
            var names: [String] = []
            var next = parent
            for _ in 0..<64 {
                guard let folder = byID[next], folder.type == 2, folder.parent != 0 else { break }
                names.insert(rootNames[folder.title] ?? folder.title, at: 0)
                next = folder.parent
            }
            return names
        }
        return rows.compactMap { row in
            guard row.type == 1, let url = row.url, !url.hasPrefix("place:") else { return nil }
            return Bookmark(title: row.title.isEmpty ? url : row.title, url: url, folder: trail(row.parent).joined(separator: " › "))
        }
    }

    /// Every profile's bookmarks. A URL found twice is listed once.
    public static func load(profilesFolder: String, fileManager: FileManager = .default) -> [Bookmark] {
        let profiles = ((try? fileManager.contentsOfDirectory(atPath: profilesFolder)) ?? []).sorted()
        var seen = Set<String>()
        var all: [Bookmark] = []
        for profile in profiles {
            let database = profilesFolder + "/" + profile + "/places.sqlite"
            guard fileManager.fileExists(atPath: database) else { continue }
            for bookmark in bookmarks(from: readRows(database, fileManager: fileManager)) where seen.insert(bookmark.url).inserted {
                all.append(bookmark)
            }
        }
        return all
    }

    /// Reads a copy of the database, with its write-ahead log, read-only.
    static func readRows(_ database: String, fileManager: FileManager) -> [Row] {
        let copy = fileManager.temporaryDirectory.appendingPathComponent("byakugan-places-\(UUID().uuidString)")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? fileManager.removeItem(atPath: copy.path + suffix) }
        }
        for suffix in ["", "-wal"] where fileManager.fileExists(atPath: database + suffix) {
            try? fileManager.copyItem(atPath: database + suffix, toPath: copy.path + suffix)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(db) }
        let sql = "SELECT b.id, b.parent, b.type, COALESCE(b.title, ''), p.url FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk = p.id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else { return [] }
        defer { sqlite3_finalize(query) }
        var rows: [Row] = []
        while sqlite3_step(query) == SQLITE_ROW {
            let title = sqlite3_column_text(query, 3).map { String(cString: $0) } ?? ""
            let url = sqlite3_column_text(query, 4).map { String(cString: $0) }
            rows.append(Row(
                id: Int(sqlite3_column_int64(query, 0)), parent: Int(sqlite3_column_int64(query, 1)),
                type: Int(sqlite3_column_int(query, 2)), title: title, url: url
            ))
        }
        return rows
    }
}
