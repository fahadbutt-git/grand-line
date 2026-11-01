import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Which item a path names: its volume and inode. Two paths that reach one
/// item (through a symbolic link such as ~/Drive, a firmlink, or a change of
/// case) give the same stamp. Kept in the Put Back ledger, so an item that
/// later takes a trashed item's place in the Trash is not taken for it.
public struct FileStamp: Codable, Hashable, Sendable {
    public let device: Int64
    public let inode: UInt64

    public init(device: Int64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    /// The item at `url`; a link itself unless `followingLink`. Nil when nothing is there.
    public static func of(_ url: URL, followingLink: Bool = false) -> FileStamp? {
        info(url, followingLink: followingLink).map { FileStamp(device: Int64(truncatingIfNeeded: $0.st_dev), inode: UInt64($0.st_ino)) }
    }

    static func info(_ url: URL, followingLink: Bool) -> stat? {
        var buffer = stat()
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return followingLink ? stat(path, &buffer) : lstat(path, &buffer)
        }
        return status == 0 ? buffer : nil
    }
}

/// Same item, same folder, inside a folder and same volume, decided by what
/// the paths reach and not by how they are spelled. A pane on ~/Drive/X (a
/// link into CloudStorage) and one on the real path show one folder.
enum FileIdentity {
    /// Links resolved and the path standardized.
    static func resolved(_ url: URL) -> URL {
        URL(fileURLWithPath: url.path).standardizedFileURL.resolvingSymlinksInPath()
    }

    /// The item itself: its folder resolved, its own name kept, so a link is
    /// the link and not what it points to.
    static func resolvedItem(_ url: URL) -> URL {
        let standard = URL(fileURLWithPath: url.path).standardizedFileURL
        let name = standard.lastPathComponent
        guard standard.path != "/", !name.isEmpty else { return standard }
        return resolved(standard.deletingLastPathComponent()).appendingPathComponent(name)
    }

    static func resourceID(_ url: URL) -> (any NSCopying & NSSecureCoding & NSObjectProtocol)? {
        // A fresh URL, so no value cached from before a move is used.
        let fresh = URL(fileURLWithPath: url.path)
        return try? fresh.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }

    /// Two folders (or what links to them point to) are one folder.
    static func sameFolder(_ a: URL, _ b: URL) -> Bool {
        let first = resolved(a)
        let second = resolved(b)
        if first.path == second.path { return true }
        if let x = resourceID(first), let y = resourceID(second), x.isEqual(y) { return true }
        if let x = FileStamp.of(first, followingLink: true), let y = FileStamp.of(second, followingLink: true) { return x == y }
        return false
    }

    /// Two paths name one item (a link compares as the link).
    static func sameItem(_ a: URL, _ b: URL) -> Bool {
        let first = resolvedItem(a)
        let second = resolvedItem(b)
        if first.path == second.path { return true }
        if let x = resourceID(first), let y = resourceID(second), x.isEqual(y) { return true }
        if let x = FileStamp.of(first), let y = FileStamp.of(second) { return x == y }
        return false
    }

    /// `url` is `folder` or inside it, by path or, for firmlinks and links on
    /// the way, by the identity of each folder above `url`.
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let base = resolved(folder)
        var current = resolved(url).path
        let basePath = base.path
        if current == basePath || current.hasPrefix(basePath.hasSuffix("/") ? basePath : basePath + "/") { return true }
        guard let target = FileStamp.of(base, followingLink: true) else { return false }
        for _ in 0..<1_024 {
            if let stamp = FileStamp.of(URL(fileURLWithPath: current), followingLink: true), stamp == target { return true }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { break }
            current = parent
        }
        return false
    }

    /// A folder and every folder above it, by resolved path and by identity:
    /// `holds` then answers "is this item one of them" without walking up
    /// again for each item of a large selection.
    struct Ancestry {
        let path: String
        let stamps: Set<FileStamp>

        init(_ folder: URL) {
            var current = FileIdentity.resolved(folder).path
            path = current
            var found = Set<FileStamp>()
            for _ in 0..<1_024 {
                if let stamp = FileStamp.of(URL(fileURLWithPath: current), followingLink: true) { found.insert(stamp) }
                let parent = (current as NSString).deletingLastPathComponent
                if parent == current || parent.isEmpty { break }
                current = parent
            }
            stamps = found
        }

        /// `item` is the folder or one above it: the folder is inside `item`.
        func holds(_ item: URL) -> Bool {
            let resolved = FileIdentity.resolved(item).path
            if path == resolved || path.hasPrefix(resolved.hasSuffix("/") ? resolved : resolved + "/") { return true }
            guard let stamp = FileStamp.of(URL(fileURLWithPath: resolved), followingLink: true) else { return false }
            return stamps.contains(stamp)
        }
    }

    /// The volume a folder is on (st_dev), following links.
    static func device(of folder: URL) -> Int64? {
        FileStamp.of(resolved(folder), followingLink: true)?.device
    }

    /// An item and a folder on one volume, so a move there is a rename.
    static func sameVolume(_ item: URL, _ folder: URL) -> Bool {
        guard let a = device(of: item.deletingLastPathComponent()), let b = device(of: folder) else { return true }
        return a == b
    }

    /// The key a name is compared by in one folder. The Mac's volumes ignore
    /// case, so "Notes" and "notes" are one name; on a volume that does not,
    /// treating them as one only gives a "notes 2" where none was needed.
    static func nameKey(_ name: String) -> String {
        name.lowercased()
    }
}
