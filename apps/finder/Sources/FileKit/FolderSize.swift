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

/// How far a measurement may go. A folder past a limit has no size (the
/// list shows "--", as Finder does with Calculate all sizes off) and is not
/// remembered, so a later look can try again.
public struct FolderSizeLimits: Sendable, Equatable {
    /// Folder levels below the measured one.
    public var maxDepth: Int
    /// Items looked at.
    public var maxEntries: Int
    /// Seconds spent on one folder.
    public var maxSeconds: Double
    /// Network volumes and cloud folders (File Provider: Google Drive,
    /// iCloud Drive), which are measured over the network; off unless asked.
    public var includeRemote: Bool

    public init(maxDepth: Int, maxEntries: Int, maxSeconds: Double, includeRemote: Bool) {
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
        self.maxSeconds = maxSeconds
        self.includeRemote = includeRemote
    }

    /// Folders in a listing, measured in the background.
    public static let listing = FolderSizeLimits(maxDepth: 64, maxEntries: 250_000, maxSeconds: 4, includeRemote: false)
    /// A size asked for (Get Info, the inspector): no limit but the volume.
    public static let unbounded = FolderSizeLimits(maxDepth: .max, maxEntries: .max, maxSeconds: .infinity, includeRemote: true)
}

/// Folder sizes, measured once and kept until a watcher event says a folder changed.
/// Every folder below the measured one is cached too, so opening a subfolder is instant.
/// A measurement never leaves the folder's volume (a mount point below it, or
/// /System/Volumes/Data below "/", is not counted), stops when its task is
/// cancelled, and keeps to its `FolderSizeLimits`.
///
/// ```swift
/// for await batch in watcher.changes { await sizes.invalidate(batch) }
/// ```
public actor FolderSize {
    private var cache: [String: FolderSizeResult] = [:]
    /// The most folders remembered. Measuring the home folder remembers every
    /// folder below it; past this, the deepest go first (the shallow ones are
    /// what panes show), so the cache stays a few MB on any disk.
    public nonisolated let maxEntries: Int

    public init(maxEntries: Int = 40_000) {
        self.maxEntries = max(1, maxEntries)
    }

    /// Folders remembered now.
    public var count: Int { cache.count }

    /// The whole size, as Get Info asks for it: within the volume, no other limit.
    public func size(of folder: URL) async -> FolderSizeResult {
        await size(of: folder, limits: .unbounded) ?? .zero
    }

    /// The size within `limits`, nil when a limit was reached, the folder is
    /// remote and `limits` leaves those out, or the task was cancelled.
    public func size(of folder: URL, limits: FolderSizeLimits) async -> FolderSizeResult? {
        let path = FolderWatcher.realPath(folder.path)
        if let known = cache[path] { return known }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        if !limits.includeRemote, Self.isRemote(root) { return nil }
        guard let device = FileStamp.of(root, followingLink: true)?.device else { return nil }
        let known = cache
        let work = Task.detached(priority: .utility) { () -> Measured in
            var walk = Walk(limits: limits, device: device, known: known)
            let (total, complete) = walk.measure(path, depth: 0)
            return Measured(total: total, complete: complete, found: walk.found)
        }
        // Cancelling the caller (a pane that moved on) stops the walk too.
        let measured = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        cache.merge(measured.found) { _, new in new }
        trim(keeping: path)
        return measured.complete ? measured.total : nil
    }

    struct Measured: Sendable {
        let total: FolderSizeResult
        let complete: Bool
        let found: [String: FolderSizeResult]
    }

    /// On a network volume, or a cloud folder whose listing comes over the network.
    public static func isRemote(_ url: URL) -> Bool {
        if isCloudPath(url.path) { return true }
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal == false
    }

    /// ~/Library/CloudStorage (File Provider: Google Drive, OneDrive, Dropbox)
    /// and ~/Library/Mobile Documents (iCloud Drive), and anything in them.
    static func isCloudPath(_ path: String) -> Bool {
        for marker in ["/Library/CloudStorage", "/Library/Mobile Documents"] {
            if path.hasSuffix(marker) || path.contains(marker + "/") { return true }
        }
        return false
    }

    /// Over `maxEntries`: keeps the shallowest three quarters, and `path`.
    private func trim(keeping path: String) {
        guard cache.count > maxEntries else { return }
        let keep = max(1, maxEntries * 3 / 4)
        let ordered = cache.keys.sorted { Self.depth($0) < Self.depth($1) }
        for key in ordered.dropFirst(keep) where key != path {
            cache.removeValue(forKey: key)
        }
    }

    static func depth(_ path: String) -> Int {
        path.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "/") ? 1 : 0) }
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

    /// One measurement: the limits it keeps to, and what it found complete.
    struct Walk {
        let limits: FolderSizeLimits
        let device: Int64
        let known: [String: FolderSizeResult]
        let deadline: Date
        var entries = 0
        var found: [String: FolderSizeResult] = [:]

        init(limits: FolderSizeLimits, device: Int64, known: [String: FolderSizeResult]) {
            self.limits = limits
            self.device = device
            self.known = known
            self.deadline = limits.maxSeconds.isFinite ? Date().addingTimeInterval(limits.maxSeconds) : .distantFuture
        }

        var stopped: Bool {
            Task.isCancelled || entries > limits.maxEntries || Date() > deadline
        }

        /// The folder's total, and whether nothing was left out by a limit.
        /// Only complete folders are remembered.
        mutating func measure(_ path: String, depth: Int) -> (FolderSizeResult, Bool) {
            if let cached = known[path] { return (cached, true) }
            if depth > limits.maxDepth || stopped { return (.zero, false) }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: FolderSize.keys, options: []
            )) ?? []
            var total = FolderSizeResult.zero
            var complete = true
            for child in children {
                entries += 1
                if entries > limits.maxEntries { return (total, false) }
                if entries & 1023 == 0, stopped { return (total, false) }
                guard let values = try? child.resourceValues(forKeys: Set(FolderSize.keys)) else { continue }
                if values.isDirectory == true, values.isSymbolicLink != true {
                    let childPath = FolderSize.join(path, child.lastPathComponent)
                    // Another volume mounted here, or a cloud folder: not this folder's size.
                    if FileStamp.of(child)?.device != device { continue }
                    if !limits.includeRemote, FolderSize.isCloudPath(childPath) { continue }
                    let (inner, innerComplete) = measure(childPath, depth: depth + 1)
                    complete = complete && innerComplete
                    total = total + inner + FolderSizeResult(bytes: 0, allocatedBytes: 0, files: 0, folders: 1)
                } else {
                    total = total + FolderSizeResult(
                        bytes: Int64(values.fileSize ?? 0),
                        allocatedBytes: Int64(values.totalFileAllocatedSize ?? 0),
                        files: 1, folders: 0
                    )
                }
                if !complete && stopped { return (total, false) }
            }
            if complete { found[path] = total }
            return (total, complete)
        }
    }

    static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }
}
