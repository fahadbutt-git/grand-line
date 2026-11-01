// The FSEvents stream setup (context pointer, callback unpacking) is adapted from
// jgvanwyk/SwiftFileSystemEvents (CC0 1.0), FileSystemEventStream.swift.
import CoreServices
import Foundation

/// Watches folders with FSEvents and publishes coalesced folder changes. FSEvents
/// already merges events within `latency`; each batch is then reduced to one change
/// per folder. Paths are real paths (`/private/var`, not `/var`).
public final class FolderWatcher: @unchecked Sendable {
    public let paths: [String]
    /// The changes, batch by batch (empty when the watcher was made with `tagged`).
    public let changes: AsyncStream<[FolderChange]>
    /// With `tagged`: each batch with the newest event it covers, so whoever
    /// applies them can store an event ID only once its changes are applied.
    public let batches: AsyncStream<WatchBatch>

    private let since: UInt64?
    private let latency: TimeInterval
    private let box: WatcherBox
    private let queue = DispatchQueue(label: "IndexKit.FolderWatcher")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    /// - Parameters:
    ///   - since: an event ID to replay from (the last one applied in an
    ///     earlier run), or nil for changes from now on.
    ///   - tagged: publish `batches` (changes with their event IDs) instead of `changes`.
    public init(paths: [String], since: UInt64? = nil, latency: TimeInterval = 0.5, tagged: Bool = false) {
        let real = paths.map(FolderWatcher.realPath)
        self.paths = real
        self.since = since
        self.latency = latency
        let (changes, continuation) = AsyncStream.makeStream(of: [FolderChange].self, bufferingPolicy: .unbounded)
        let (batches, batchContinuation) = AsyncStream.makeStream(of: WatchBatch.self, bufferingPolicy: .unbounded)
        self.changes = changes
        self.batches = batches
        // Only one stream is fed; the other ends at once, so nothing piles up unread.
        if tagged { continuation.finish() } else { batchContinuation.finish() }
        self.box = WatcherBox(continuation: continuation, latest: since ?? FolderWatcher.currentEventID, roots: real,
                              batches: tagged ? batchContinuation : nil)
    }

    deinit {
        stop()
        box.continuation.finish()
        box.batches?.finish()
    }

    /// The system's newest event ID, to store with a snapshot.
    public static var currentEventID: UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// The newest event this watcher has seen, which may not be applied yet:
    /// what to store comes from `batches`.
    public var latestEventID: UInt64 {
        box.latestEventID
    }

    /// The FSEvents UUID of the volume holding `path`: it changes when the disk
    /// is erased or restored, which makes stored event IDs meaningless.
    public static func volumeUUID(of path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return uuidString(FSEventsCopyUUIDForDevice(info.st_dev))
    }

    /// The volume UUID of each path that has one.
    public static func volumeUUIDs(for paths: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for path in paths {
            if let uuid = volumeUUID(of: path) { result[path] = uuid }
        }
        return result
    }

    // The SDK has imported FSEventsCopyUUIDForDevice both as a managed and an
    // unmanaged reference; one of these two fits whichever this SDK uses.
    private static func uuidString(_ uuid: Unmanaged<CFUUID>?) -> String? {
        guard let uuid else { return nil }
        let value = uuid.takeRetainedValue()
        return CFUUIDCreateString(kCFAllocatorDefault, value) as String?
    }

    private static func uuidString(_ uuid: CFUUID?) -> String? {
        guard let uuid else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }

    /// Resolves symbolic links the way FSEvents reports paths. Missing paths come back standardized.
    public static func realPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard let resolved = realpath(expanded, nil) else {
            return FolderChange.normalize((expanded as NSString).standardizingPath)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Returns false when the stream could not start.
    @discardableResult
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return true }

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, eventIDs in
            guard let info else { return }
            let box = Unmanaged<WatcherBox>.fromOpaque(info).takeUnretainedValue()
            let cPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var events: [(String, FSEventStreamEventFlags, FSEventStreamEventId)] = []
            events.reserveCapacity(count)
            for i in 0..<count {
                events.append((String(cString: cPaths[i]), eventFlags[i], eventIDs[i]))
            }
            box.receive(events)
        }

        let info = Unmanaged.passRetained(box).toOpaque()
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<WatcherBox>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            since ?? UInt64.max, // kFSEventStreamEventIdSinceNow
            latency,
            flags
        ) else {
            Unmanaged<WatcherBox>.fromOpaque(info).release()
            return false
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return false
        }
        stream = created
        return true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Turns raw FSEvents flags into changes, by `IndexRecovery.event`. Dropped
    /// events and a wrapped counter ask for every root again (each root as one
    /// recursive change; with no roots given, the event's own path). Exposed for tests.
    static func changes(
        from events: [(String, FSEventStreamEventFlags, FSEventStreamEventId)],
        roots: [String] = []
    ) -> [FolderChange] {
        var changes: [FolderChange] = []
        for (path, flags, _) in events {
            switch IndexRecovery.event(path: path, flags: flags) {
            case .ignore:
                continue
            case .folder(let folder):
                changes.append(FolderChange(path: folder))
            case .subtree(let folder):
                changes.append(FolderChange(path: folder, recursive: true))
            case .roots, .rebuild:
                if roots.isEmpty {
                    changes.append(FolderChange(path: path, recursive: true))
                } else {
                    changes += roots.map { FolderChange(path: $0, recursive: true) }
                }
            }
        }
        return FolderChange.coalesce(changes)
    }
}

/// One batch of changes and the newest FSEvents event it covers. A batch whose
/// events all changed nothing has no changes but still moves the event on.
public struct WatchBatch: Sendable, Equatable {
    public let changes: [FolderChange]
    public let eventID: UInt64

    public init(changes: [FolderChange], eventID: UInt64) {
        self.changes = changes
        self.eventID = eventID
    }
}

/// Lives as long as the stream, which owns one reference to it.
final class WatcherBox: @unchecked Sendable {
    let continuation: AsyncStream<[FolderChange]>.Continuation
    let batches: AsyncStream<WatchBatch>.Continuation?
    let roots: [String]
    private let lock = NSLock()
    private var latest: UInt64

    init(continuation: AsyncStream<[FolderChange]>.Continuation, latest: UInt64, roots: [String] = [],
         batches: AsyncStream<WatchBatch>.Continuation? = nil) {
        self.continuation = continuation
        self.batches = batches
        self.latest = latest
        self.roots = roots
    }

    var latestEventID: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func receive(_ events: [(String, FSEventStreamEventFlags, FSEventStreamEventId)]) {
        let newest = events.map({ $0.2 }).max()
        if let newest {
            lock.lock()
            latest = max(latest, newest)
            lock.unlock()
        }
        let changes = FolderWatcher.changes(from: events, roots: roots)
        if let batches {
            if let newest { batches.yield(WatchBatch(changes: changes, eventID: newest)) }
        } else if !changes.isEmpty {
            continuation.yield(changes)
        }
    }
}
