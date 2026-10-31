import CoreServices
import Foundation

/// How the index stays trustworthy across restarts and lost events, as pure
/// decisions the service acts on.
///
/// FSEvents keeps a history per volume, so an index saved with the last event it
/// applied can catch up after a restart instead of walking the disk again. The
/// history is no good when the volume is not the one the snapshot came from (a
/// restored or reformatted disk has a new UUID) or when the system's event
/// counter is behind the stored one; then the folders are walked again while the
/// old index keeps answering.
public enum IndexRecovery {
    public enum Reason: Equatable, Sendable {
        /// The snapshot was saved part way through a walk.
        case incomplete
        /// The disk holding this root is not the one the snapshot was made on.
        case volumeChanged(root: String)
        /// The system's newest event is older than the one stored.
        case eventIDWentBackwards
        /// The snapshot stores no event to catch up from.
        case noHistory
    }

    public enum Startup: Equatable, Sendable {
        /// Nothing to show yet: walk everything, publishing as it goes.
        case build
        /// The snapshot is good: replay FSEvents from this event.
        case resume(since: UInt64)
        /// Keep answering from the snapshot while a new walk runs.
        case rebuild(Reason)
    }

    /// What to do with a loaded snapshot.
    /// - Parameters:
    ///   - storedVolumes: the volume UUID of each root saved with the snapshot
    ///     (empty for snapshots from before UUIDs were saved: those resume).
    ///   - currentVolumes: the volume UUID of each root now (a root missing here
    ///     could not be checked, and does not force a rebuild).
    public static func startup(
        count: Int, complete: Bool, storedEventID: UInt64, currentEventID: UInt64,
        roots: [String], storedVolumes: [String: String], currentVolumes: [String: String]
    ) -> Startup {
        if count == 0 { return .build }
        if !complete { return .rebuild(.incomplete) }
        if storedEventID == 0 { return .rebuild(.noHistory) }
        for root in roots {
            if let stored = storedVolumes[root], let current = currentVolumes[root], stored != current {
                return .rebuild(.volumeChanged(root: root))
            }
        }
        if currentEventID < storedEventID { return .rebuild(.eventIDWentBackwards) }
        return .resume(since: storedEventID)
    }

    /// What one FSEvents event asks for.
    public enum Event: Equatable, Sendable {
        /// History replay finished, or nothing to do.
        case ignore
        /// The folder's own entries changed.
        case folder(String)
        /// Anything below the folder may have changed (MustScanSubDirs), or the
        /// watched root itself was moved, deleted or made again (RootChanged).
        case subtree(String)
        /// Events were dropped (UserDropped, KernelDropped): every root again.
        case roots
        /// The event counter wrapped: history is meaningless, walk everything.
        case rebuild
    }

    public static func event(path: String, flags: FSEventStreamEventFlags) -> Event {
        func has(_ flag: Int) -> Bool { flags & FSEventStreamEventFlags(flag) != 0 }
        if has(kFSEventStreamEventFlagEventIdsWrapped) { return .rebuild }
        if has(kFSEventStreamEventFlagUserDropped) || has(kFSEventStreamEventFlagKernelDropped) { return .roots }
        if has(kFSEventStreamEventFlagRootChanged) || has(kFSEventStreamEventFlagMustScanSubDirs) {
            return .subtree(path)
        }
        if has(kFSEventStreamEventFlagHistoryDone) { return .ignore }
        if path.isEmpty { return .ignore }
        return .folder(path)
    }

    /// Whether a weekly sweep (a quiet full walk that catches anything the
    /// events missed) is due.
    public static func sweepDue(last: Date?, now: Date, every: TimeInterval = 7 * 86_400) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) >= every || now < last
    }
}
