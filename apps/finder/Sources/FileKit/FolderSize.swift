import Foundation
import IndexKit

public struct FolderSizeResult: Sendable, Equatable {
    /// Sum of file sizes, as Finder's "Size".
    public let bytes: Int64
    /// Space used on disk.
    public let allocatedBytes: Int64
    public let files: Int
    public let folders: Int

    public init(bytes: Int64, allocatedBytes: Int64, files: Int, folders: Int) {
        self.bytes = bytes
        self.allocatedBytes = allocatedBytes
        self.files = files
        self.folders = folders
    }

    static let zero = FolderSizeResult(bytes: 0, allocatedBytes: 0, files: 0, folders: 0)

    static func + (a: FolderSizeResult, b: FolderSizeResult) -> FolderSizeResult {
        FolderSizeResult(
            bytes: a.bytes + b.bytes, allocatedBytes: a.allocatedBytes + b.allocatedBytes,
            files: a.files + b.files, folders: a.folders + b.folders
        )
    }
}

/// Folder sizes, measured once and kept until a watcher event says a folder changed.
/// Every folder below the measured one is cached too, so opening a subfolder is instant.
///
/// ```swift
/// for await batch in watcher.changes { await sizes.invalidate(batch) }
/// ```
public actor FolderSize {
    private var cache: [String: FolderSizeResult] = [:]

    public init() {}

    public func size(of folder: URL) async -> FolderSizeResult {
        let path = FolderWatcher.realPath(folder.path)
        if let known = cache[path] { return known }
        let known = cache
        let measured = await Task.detached(priority: .utility) {
            var found: [String: FolderSizeResult] = [:]
            let total = FolderSize.measure(path, known: known, into: &found)
            return (total, found)
        }.value
        cache.merge(measured.1) { _, new in new }
        return measured.0
    }

    public func cached(_ folder: URL) -> FolderSizeResult? {
        cache[FolderWatcher.realPath(folder.path)]
    }

    /// A change to a folder makes it and every folder above it stale; a recursive
    /// change makes everything below it stale too.
    public func invalidate(_ changes: [FolderChange]) {
        for change in changes {
            var path = change.path
            while true {
                cache.removeValue(forKey: path)
                if path == "/" || path.isEmpty { break }
                path = (path as NSString).deletingLastPathComponent
            }
            if change.recursive {
                let stale = cache.keys.filter { FolderChange.isInside($0, change.path) }
                for key in stale { cache.removeValue(forKey: key) }
            }
        }
    }

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey]

    static func measure(
        _ path: String,
        known: [String: FolderSizeResult],
        into found: inout [String: FolderSizeResult]
    ) -> FolderSizeResult {
        if let cached = known[path] { return cached }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: []
        )) ?? []
        var total = FolderSizeResult.zero
        for child in children {
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true, values.isSymbolicLink != true {
                let inner = measure(join(path, child.lastPathComponent), known: known, into: &found)
                total = total + inner + FolderSizeResult(bytes: 0, allocatedBytes: 0, files: 0, folders: 1)
            } else {
                total = total + FolderSizeResult(
                    bytes: Int64(values.fileSize ?? 0),
                    allocatedBytes: Int64(values.totalFileAllocatedSize ?? 0),
                    files: 1, folders: 0
                )
            }
        }
        found[path] = total
        return total
    }

    static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }
}
