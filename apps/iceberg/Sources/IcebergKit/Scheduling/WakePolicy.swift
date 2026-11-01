import Foundation

/// The small decisions that keep Iceberg from waking the Mac for nothing.
public enum WakePolicy {
    /// How late a one-shot timer may fire: a tenth of its delay (at least
    /// half a second), so macOS can fold the wake-up in with others.
    public static func tolerance(forDelay delay: TimeInterval) -> TimeInterval {
        max(0.5, delay * 0.1)
    }

    /// Whether the closed notch's playing bars move. They rest while nothing
    /// plays, with Reduce Motion, in Low Power Mode and while the displays
    /// sleep, so the closed notch draws no frames then.
    public static func barsMove(playing: Bool, reduceMotion: Bool, lowPower: Bool, displaysAsleep: Bool) -> Bool {
        playing && !reduceMotion && !lowPower && !displaysAsleep
    }

    /// How long a stream widget's reader waits for output before looking
    /// again, in milliseconds. With a line held back (the script prints
    /// faster than `minimumInterval`), until it may be shown; once the
    /// command has exited, briefly (the last output is collected); otherwise
    /// it sleeps until output comes, waking every few seconds only to notice
    /// a command that ended while something it started keeps its output open.
    public static func streamPollTimeout(pending: Bool, lastDelivered: Date, minimumInterval: TimeInterval,
                                         exited: Bool, now: Date) -> Int32 {
        if exited { return 50 }
        if pending {
            let wait = lastDelivered.addingTimeInterval(minimumInterval).timeIntervalSince(now)
            return Int32(max(1, min(idleWaitMilliseconds, Int((wait * 1000).rounded(.up)))))
        }
        return Int32(idleWaitMilliseconds)
    }

    /// The reader's wait with nothing to do.
    public static let idleWaitMilliseconds = 5_000
}

/// Asking for Calendar or Reminders access: one macOS prompt at a time, and
/// not two in a row, so opening the panel the first time never shows a wall
/// of permission dialogs. A widget that may not ask now asks on a later open.
public struct PromptPacing: Equatable, Sendable {
    /// Time after one prompt is answered before another may show.
    public static let gap: TimeInterval = 20

    public private(set) var asking = false
    public private(set) var lastAnswered: Date?

    public init() {}

    public mutating func mayAsk(at now: Date) -> Bool {
        if asking { return false }
        if let last = lastAnswered, now.timeIntervalSince(last) < Self.gap { return false }
        asking = true
        return true
    }

    public mutating func answered(at now: Date) {
        asking = false
        lastAnswered = now
    }
}
