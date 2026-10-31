import Foundation

/// What the info bar says about a selection.
public struct SelectionSummary: Sendable, Equatable {
    public let count: Int
    public let files: Int
    public let folders: Int
    /// Files plus the contents of folders.
    public let totalBytes: Int64
    /// Kind ("PDF document", "Folder") to how many.
    public let kinds: [String: Int]
    public let oldest: Date?
    public let newest: Date?
    /// Tags every item has.
    public let commonTags: [String]
    /// The deepest folder holding every item.
    public let commonParent: URL?

    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .localizedTypeDescriptionKey,
        .contentModificationDateKey, .tagNamesKey,
    ]

    /// Folder sizes come from `sizes`, so a cached size is reused.
    public static func make(for items: [URL], sizes: FolderSize = FolderSize()) async -> SelectionSummary {
        var files = 0
        var folders = 0
        var bytes: Int64 = 0
        var kinds: [String: Int] = [:]
        var oldest: Date?
        var newest: Date?
        var tags: Set<String>?
        for item in items {
            let values = try? item.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                folders += 1
                bytes += await sizes.size(of: item).bytes
            } else {
                files += 1
                bytes += Int64(values?.fileSize ?? 0)
            }
            let kind = values?.localizedTypeDescription ?? (values?.isDirectory == true ? "Folder" : "Document")
            kinds[kind, default: 0] += 1
            if let date = values?.contentModificationDate {
                oldest = min(oldest ?? date, date)
                newest = max(newest ?? date, date)
            }
            let itemTags = Set(values?.tagNames ?? [])
            tags = tags.map { $0.intersection(itemTags) } ?? itemTags
        }
        return SelectionSummary(
            count: items.count, files: files, folders: folders, totalBytes: bytes, kinds: kinds,
            oldest: oldest, newest: newest, commonTags: (tags ?? []).sorted(), commonParent: commonParent(of: items)
        )
    }

    static func commonParent(of items: [URL]) -> URL? {
        let parents = items.map { FilePath.canonical($0).deletingLastPathComponent().pathComponents }
        guard var shared = parents.first else { return nil }
        for parts in parents.dropFirst() {
            var length = 0
            while length < shared.count, length < parts.count, shared[length] == parts[length] { length += 1 }
            shared = Array(shared.prefix(length))
        }
        guard !shared.isEmpty else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: shared), isDirectory: true)
    }
}
