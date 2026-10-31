import ArchiveKit
import Foundation
import UniformTypeIdentifiers

/// Rows for a folder inside an archive (R26), from ArchiveKit's listing.
public enum ArchiveRows {
    /// nil when `entry` is not a folder in the archive.
    public static func items(in listing: ArchiveListing, at entry: String) -> [FileItem]? {
        guard let folder = listing.item(at: entry), folder.isFolder else { return nil }
        return folder.children.map { row($0, archive: listing.archive) }
    }

    static func row(_ child: ArchiveItem, archive: URL) -> FileItem {
        let ext = (child.name as NSString).pathExtension
        let type = child.isFolder ? UTType.folder : UTType(filenameExtension: ext)
        return FileItem(
            url: archive.appendingPathComponent(child.path),
            name: child.name,
            isFolder: child.isFolder,
            size: child.size,
            modified: child.modified,
            kind: child.isFolder ? "Folder" : (type?.localizedDescription ?? "Document"),
            typeIdentifier: type?.identifier,
            archiveEntry: child.path
        )
    }

    /// The archive entries to extract for the selected rows.
    public static func entries(_ items: [FileItem]) -> [String] {
        items.compactMap(\.archiveEntry)
    }
}
