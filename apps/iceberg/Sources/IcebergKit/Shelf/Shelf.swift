import Foundation

/// One file on the shelf. Only a bookmark to the file is kept (and its last
/// known path and name, to show while the bookmark resolves); the file
/// itself is never copied, moved or deleted by the shelf.
public struct ShelfItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Where the file was when last seen.
    public var path: String
    /// `URL.bookmarkData()`, which follows the file when it is renamed or moved.
    public var bookmark: Data
    public var added: Date

    public init(id: String = UUID().uuidString, name: String, path: String, bookmark: Data, added: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.added = added
    }
}

/// The shelf's list, newest first, without the same file twice.
public struct ShelfList: Equatable, Sendable {
    /// More than this and the oldest fall off the shelf (only the bookmark
    /// goes; the file is untouched).
    public static let maxItems = 60

    public private(set) var items: [ShelfItem]

    public init(items: [ShelfItem] = []) {
        var seen = Set<String>()
        self.items = Array(items.filter { seen.insert(Self.key($0.path)).inserted }.prefix(Self.maxItems))
    }

    /// Paths compared as macOS sees them: standardised, case kept.
    static func key(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public func contains(path: String) -> Bool {
        let k = Self.key(path)
        return items.contains { Self.key($0.path) == k }
    }

    /// Adds the new items in front, in the order given. A file already on
    /// the shelf moves to the front instead of showing twice. Returns the
    /// ids of the items that are new.
    @discardableResult
    public mutating func add(_ new: [ShelfItem]) -> [String] {
        var added: [String] = []
        var front: [ShelfItem] = []
        for item in new {
            let k = Self.key(item.path)
            if front.contains(where: { Self.key($0.path) == k }) { continue }
            if let existing = items.first(where: { Self.key($0.path) == k }) {
                front.append(existing)
            } else {
                front.append(item)
                added.append(item.id)
            }
        }
        let keys = Set(front.map { Self.key($0.path) })
        items = Array((front + items.filter { !keys.contains(Self.key($0.path)) }).prefix(Self.maxItems))
        return added.filter { id in items.contains { $0.id == id } }
    }

    /// Takes an item off the shelf. The file stays where it is.
    public mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    /// Empties the shelf. No file is touched.
    public mutating func removeAll() {
        items.removeAll()
    }

    /// The file moved or was renamed: keep the new path and bookmark.
    public mutating func update(id: String, path: String, name: String, bookmark: Data?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].path = path
        items[i].name = name
        if let bookmark { items[i].bookmark = bookmark }
    }
}

/// The shelf's file, `~/.local/state/grand-line/iceberg/shelf.json`.
public enum ShelfFile {
    public static let version = 1
    /// A shelf is a few kilobytes; a larger file is not read.
    public static let maxFileSize = 4 * 1024 * 1024

    struct Stored: Codable {
        var version: Int
        var items: [ShelfItem]
    }

    public static func encode(_ list: ShelfList) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(Stored(version: version, items: list.items))) ?? Data()
    }

    /// nil when the data is not a shelf file Iceberg can read.
    public static func decode(_ data: Data) -> ShelfList? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data), stored.version <= version else { return nil }
        return ShelfList(items: stored.items)
    }

    /// Reads the shelf; a missing or unreadable file is an empty shelf.
    public static func load(from url: URL) -> ShelfList {
        guard case .success(let data) = SafeFileRead.read(url, limit: maxFileSize) else { return ShelfList() }
        return decode(data) ?? ShelfList()
    }

    /// Writes the shelf in one step (a temporary file renamed over the old one).
    public static func save(_ list: ShelfList, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(list).write(to: url, options: .atomic)
    }
}

#if canImport(Darwin)
/// Making and following bookmarks (macOS only).
public enum ShelfBookmark {
    /// A shelf item for a file, or nil when macOS cannot make a bookmark.
    public static func item(for url: URL, now: Date = Date()) -> ShelfItem? {
        let file = url.standardizedFileURL
        guard let data = try? file.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        return ShelfItem(name: file.lastPathComponent, path: file.path, bookmark: data, added: now)
    }

    /// Where the file is now. `stale` means the bookmark should be made again.
    /// nil when the file is gone (or on a disk that is not mounted: nothing
    /// is mounted and no dialog is shown).
    public static func resolve(_ item: ShelfItem) -> (url: URL, stale: Bool)? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: url.path) {
            return (url, stale)
        }
        // A bookmark that no longer resolves: the file may still be at its path.
        if FileManager.default.fileExists(atPath: item.path) {
            return (URL(fileURLWithPath: item.path), true)
        }
        return nil
    }
}
#endif
