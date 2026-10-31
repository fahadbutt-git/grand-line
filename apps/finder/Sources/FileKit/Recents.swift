import Foundation

/// Log Pose's own list of recently opened items, newest first, one entry per path.
/// Kept as JSON in Application Support, so it does not depend on Spotlight.
public actor Recents {
    public struct Item: Codable, Sendable, Equatable {
        public let path: String
        public let opened: Date

        public var url: URL { URL(fileURLWithPath: path) }
    }

    public nonisolated let file: URL
    public nonisolated let limit: Int
    private var items: [Item]?

    public static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Log Pose/recents.json")
    }

    public init(file: URL = Recents.defaultFile, limit: Int = 500) {
        self.file = file
        self.limit = limit
    }

    public func record(_ url: URL, at date: Date = Date()) throws {
        let path = url.standardizedFileURL.path
        var list = load().filter { $0.path != path }
        list.insert(Item(path: path, opened: date), at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        try save(list)
    }

    /// Newest first. Items whose files are gone are left out unless `includingMissing`.
    public func list(includingMissing: Bool = false) -> [Item] {
        let all = load()
        return includingMissing ? all : all.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func remove(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        try save(load().filter { $0.path != path })
    }

    public func clear() throws {
        try save([])
    }

    private func load() -> [Item] {
        if let items { return items }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? Data(contentsOf: file)).flatMap { try? decoder.decode([Item].self, from: $0) } ?? []
        items = loaded
        return loaded
    }

    private func save(_ list: [Item]) throws {
        items = list
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(list).write(to: file, options: .atomic)
    }
}
