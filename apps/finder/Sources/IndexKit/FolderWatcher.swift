// The FSEvents stream setup (context pointer, callback unpacking) is adapted from
// jgvanwyk/SwiftFileSystemEvents (CC0 1.0), FileSystemEventStream.swift.
import CoreServices
import Foundation

/// Watches folders with FSEvents and publishes coalesced folder changes. FSEvents
/// already merges events within `latency`; each batch is then reduced to one change
/// per folder. Paths are real paths (`/private/var`, not `/var`).
public final class FolderWatcher: @unchecked Sendable {
    public let paths: [String]
    public let changes: AsyncStream<[FolderChange]>

    private let since: UInt64?
    private let latency: TimeInterval
    private let box: WatcherBox
    private let queue = DispatchQueue(label: "IndexKit.FolderWatcher")
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    /// - Parameter since: an event ID to replay from (from `latestEventID` of an earlier
    ///   run), or nil for changes from now on.
    public init(paths: [String], since: UInt64? = nil, latency: TimeInterval = 0.5) {
        self.paths = paths.map(FolderWatcher.realPath)
        self.since = since
        self.latency = latency
        let (changes, continuation) = AsyncStream.makeStream(of: [FolderChange].self, bufferingPolicy: .unbounded)
        self.changes = changes
        self.box = WatcherBox(continuation: continuation, latest: since ?? FolderWatcher.currentEventID)
    }

    deinit {
        stop()
        box.continuation.finish()
    }

    /// The system's newest event ID, to store with a snapshot.
    public static var currentEventID: UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// The newest event this watcher has seen.
    public var latestEventID: UInt64 {
        box.latestEventID
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

    /// Turns raw FSEvents flags into changes. Exposed for tests.
    static func changes(from events: [(String, FSEventStreamEventFlags, FSEventStreamEventId)]) -> [FolderChange] {
        let deep = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
                | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        )
        let ignored = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone | kFSEventStreamEventFlagEventIdsWrapped)
        var changes: [FolderChange] = []
        for (path, flags, _) in events where flags & ignored == 0 || flags & deep != 0 {
            changes.append(FolderChange(path: path, recursive: flags & deep != 0))
        }
        return FolderChange.coalesce(changes)
    }
}

/// Lives as long as the stream, which owns one reference to it.
final class WatcherBox: @unchecked Sendable {
    let continuation: AsyncStream<[FolderChange]>.Continuation
    private let lock = NSLock()
    private var latest: UInt64

    init(continuation: AsyncStream<[FolderChange]>.Continuation, latest: UInt64) {
        self.continuation = continuation
        self.latest = latest
    }

    var latestEventID: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func receive(_ events: [(String, FSEventStreamEventFlags, FSEventStreamEventId)]) {
        if let newest = events.map({ $0.2 }).max() {
            lock.lock()
            latest = max(latest, newest)
            lock.unlock()
        }
        let changes = FolderWatcher.changes(from: events)
        if !changes.isEmpty { continuation.yield(changes) }
    }
}
