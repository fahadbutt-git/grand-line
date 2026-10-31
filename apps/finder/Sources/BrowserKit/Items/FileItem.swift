import Foundation
import UniformTypeIdentifiers

/// One row in a pane: a file, a folder, or an entry inside an archive.
public struct FileItem: Hashable, Sendable, Identifiable {
    public let url: URL
    public let name: String
    /// A folder you can open. Packages (apps, bundles) count as files, as in Finder.
    public let isFolder: Bool
    public let isPackage: Bool
    public let isAlias: Bool
    /// File size in bytes; nil for folders, whose size comes from FileKit's FolderSize.
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    /// When the item arrived in its folder (Finder's Date Added).
    public let added: Date?
    /// "PDF document", "Folder".
    public let kind: String
    public let typeIdentifier: String?
    public let tags: [String]
    public let isHidden: Bool
    /// The path inside an archive when this item lives in one; `url` is then the
    /// archive's URL with that path appended, which never exists on disk.
    public let archiveEntry: String?

    public init(
        url: URL, name: String, isFolder: Bool, isPackage: Bool = false, isAlias: Bool = false,
        size: Int64? = nil, modified: Date? = nil, created: Date? = nil, added: Date? = nil, kind: String = "",
        typeIdentifier: String? = nil, tags: [String] = [], isHidden: Bool = false, archiveEntry: String? = nil
    ) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.isAlias = isAlias
        self.size = size
        self.modified = modified
        self.created = created
        self.added = added
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.tags = tags
        self.isHidden = isHidden
        self.archiveEntry = archiveEntry
    }

    public var id: String {
        if let archiveEntry { return url.path + "#" + archiveEntry }
        return url.path
    }

    public var path: String { url.path }

    /// Lowercased extension without the dot.
    public var ext: String { (name as NSString).pathExtension.lowercased() }

    public var isInArchive: Bool { archiveEntry != nil }

    static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey, .localizedTypeDescriptionKey,
        .contentTypeKey, .tagNamesKey, .isHiddenKey,
    ]

    /// Reads an item from disk; nil when it is gone.
    public static func read(_ url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false
        let isFolder = isDirectory && !isPackage
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            isFolder: isFolder,
            isPackage: isPackage,
            isAlias: (values.isAliasFile ?? false) || (values.isSymbolicLink ?? false),
            size: isFolder ? nil : Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate,
            created: values.creationDate,
            added: values.addedToDirectoryDate,
            kind: values.localizedTypeDescription ?? (isFolder ? "Folder" : "Document"),
            typeIdentifier: values.contentType?.identifier,
            tags: values.tagNames ?? [],
            isHidden: (values.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
        )
    }
}
