import Foundation

/// Numbers background reads, so only the newest one's answer is used: the
/// front app's menus read for app A must not land after the window opened
/// again for app B.
public final class LatestOnly: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    public init() {}

    /// Starts a new read; every earlier one is stale from now on.
    public func next() -> Int {
        lock.withLock {
            current += 1
            return current
        }
    }

    public func isCurrent(_ ticket: Int) -> Bool {
        lock.withLock { ticket == current }
    }

    /// Runs `apply` only while `ticket` is the newest read, under the lock, so
    /// a read started meanwhile cannot slip in between the check and the change.
    /// Returns whether it ran.
    @discardableResult
    public func ifCurrent(_ ticket: Int, _ apply: () -> Void) -> Bool {
        lock.withLock {
            guard ticket == current else { return false }
            apply()
            return true
        }
    }
}
