import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Walks and copies file trees one file at a time, so copies can report progress.
enum FileTree {
    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]

    /// Files (links count as files) and their total size.
    static func measure(_ url: URL) -> (files: Int, bytes: Int64) {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return (0, 0) }
        if values.isDirectory == true, values.isSymbolicLink != true {
            var files = 0
            var bytes: Int64 = 0
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: []
            )) ?? []
            for child in children {
                let (f, b) = measure(child)
                files += f
                bytes += b
            }
            return (files, bytes)
        }
        return (1, Int64(values.fileSize ?? 0))
    }

    /// Copies a file or folder. Files go through `FileManager.copyItem`
    /// (copyfile(3): cloned on APFS, with every extended attribute, the
    /// quarantine flag, ACLs and Finder info). Folders are made here, one level
    /// at a time so progress can be reported, and then get the same metadata
    /// from copyfile(3) (`copyFolderDetails`). `created` is called once the
    /// destination exists, so a caller knows a half copy there is its own.
    /// A folder is never copied into itself: a level that turns out to be the
    /// copy being made (through a link) stops the copy.
    static func copy(_ source: URL, to destination: URL, created: () -> Void = {}, onFile: (URL, Int64) throws -> Void) throws {
        try copy(source, to: destination, top: nil, created: created, onFile: onFile)
    }

    private static func copy(_ source: URL, to destination: URL, top: FileStamp?, created: () -> Void,
                             onFile: (URL, Int64) throws -> Void) throws {
        let values = try source.resourceValues(forKeys: Set(keys))
        let fileManager = FileManager.default
        if values.isDirectory == true, values.isSymbolicLink != true {
            try Task.checkCancellation()
            if let top, FileStamp.of(source, followingLink: true) == top {
                throw FileOperationError.intoItself(source)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            created()
            let root = top ?? FileStamp.of(destination, followingLink: true)
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: [])
            for child in children {
                try copy(child, to: destination.appendingPathComponent(child.lastPathComponent), top: root, created: {}, onFile: onFile)
            }
            copyFolderDetails(from: source, to: destination)
        } else {
            try fileManager.copyItem(at: source, to: destination)
            created()
            try onFile(source, Int64(values.fileSize ?? 0))
        }
    }

    /// A folder's metadata, set after its contents so the dates stick:
    /// copyfile(3) with ACL, STAT and XATTR (COPYFILE_METADATA: permissions,
    /// flags such as hidden, every extended attribute including
    /// com.apple.quarantine, Finder info and a custom icon), then the dates
    /// and tags again in case the volume took only some of them.
    static func copyFolderDetails(from source: URL, to destination: URL) {
        #if canImport(Darwin)
        let flags = copyfile_flags_t(COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR)
        _ = source.withUnsafeFileSystemRepresentation { from -> Int32 in
            destination.withUnsafeFileSystemRepresentation { to -> Int32 in
                guard let from, let to else { return -1 }
                return copyfile(from, to, nil, flags)
            }
        }
        #endif
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: source.path) {
            var kept: [FileAttributeKey: Any] = [:]
            for key in [FileAttributeKey.posixPermissions, .modificationDate, .creationDate] {
                if let value = attributes[key] { kept[key] = value }
            }
            try? fileManager.setAttributes(kept, ofItemAtPath: destination.path)
        }
        if let tags = try? source.resourceValues(forKeys: [.tagNamesKey]).tagNames, !tags.isEmpty,
           (try? destination.resourceValues(forKeys: [.tagNamesKey]).tagNames) != tags {
            try? (destination as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }

    static func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// A folder (or package) that is not a link to one.
    static func isRealFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    /// `url` is `folder` or inside it, whatever links or firmlinks lead there.
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        FileIdentity.isInside(url, folder)
    }
}
