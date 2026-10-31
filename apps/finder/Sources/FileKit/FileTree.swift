import Foundation

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

    /// Copies a file or folder. Files are cloned on APFS. Folders keep their dates,
    /// permissions and extended attributes (tags).
    static func copy(_ source: URL, to destination: URL, onFile: (URL, Int64) throws -> Void) throws {
        let values = try source.resourceValues(forKeys: Set(keys))
        let fileManager = FileManager.default
        if values.isDirectory == true, values.isSymbolicLink != true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
            let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: keys, options: [])
            for child in children {
                try copy(child, to: destination.appendingPathComponent(child.lastPathComponent), onFile: onFile)
            }
            copyFolderDetails(from: source, to: destination)
        } else {
            try fileManager.copyItem(at: source, to: destination)
            try onFile(source, Int64(values.fileSize ?? 0))
        }
    }

    /// Dates, permissions and Finder tags, set after the contents so the date sticks.
    static func copyFolderDetails(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        if let attributes = try? fileManager.attributesOfItem(atPath: source.path) {
            var kept: [FileAttributeKey: Any] = [:]
            for key in [FileAttributeKey.posixPermissions, .modificationDate, .creationDate] {
                if let value = attributes[key] { kept[key] = value }
            }
            try? fileManager.setAttributes(kept, ofItemAtPath: destination.path)
        }
        if let tags = try? source.resourceValues(forKeys: [.tagNamesKey]).tagNames, !tags.isEmpty {
            try? (destination as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        }
    }

    static func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = folder.standardizedFileURL.path
        return path == base || path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }
}
