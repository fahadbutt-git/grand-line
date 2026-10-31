import Foundation

/// Decides when each user widget runs. It holds no timer: the app asks
/// `nextWakeup` and arms one timer for that moment, so nothing wakes the Mac
/// in between, and nothing at all while the panel is closed.
///
/// - `on open` widgets run each time the panel opens (at most once every
///   `onOpenThrottle` seconds, so brushing past the notch does not re-run them).
/// - Interval widgets run while the panel is open. When it opens, any whose
///   value is older than its interval runs at once; the rest keep their value.
/// - While the panel is closed nothing is due.
public final class RefreshScheduler {
    public static let onOpenThrottle: TimeInterval = 3

    struct Entry {
        var policy: RefreshPolicy
        var lastRun: Date?
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    public private(set) var isOpen = false

    public init() {}

    /// Replaces the widget list. Widgets that stay, with the same policy, keep
    /// the time they last ran.
    public func setWidgets(_ widgets: [(id: String, policy: RefreshPolicy)]) {
        var next: [String: Entry] = [:]
        var nextOrder: [String] = []
        for w in widgets where next[w.id] == nil {
            let kept = entries[w.id].flatMap { $0.policy == w.policy ? $0.lastRun : nil }
            next[w.id] = Entry(policy: w.policy, lastRun: kept)
            nextOrder.append(w.id)
        }
        entries = next
        order = nextOrder
    }

    public var widgetIDs: [String] { order }

    public func lastRun(of id: String) -> Date? { entries[id]?.lastRun }

    /// The panel opened: the widgets to run now, already marked as run.
    public func panelOpened(at now: Date) -> [String] {
        isOpen = true
        var run: [String] = []
        for id in order {
            guard let e = entries[id] else { continue }
            let stale: Bool
            switch e.policy {
            case .onOpen:
                stale = e.lastRun.map { now.timeIntervalSince($0) >= Self.onOpenThrottle } ?? true
            case .interval(let s):
                stale = e.lastRun.map { now.timeIntervalSince($0) >= s } ?? true
            }
            if stale { run.append(id); entries[id]?.lastRun = now }
        }
        return run
    }

    public func panelClosed() { isOpen = false }

    /// Interval widgets due at `now` (none while closed), already marked as run.
    public func due(at now: Date) -> [String] {
        guard isOpen else { return [] }
        var run: [String] = []
        for id in order {
            guard let e = entries[id], case .interval(let s) = e.policy else { continue }
            let next = (e.lastRun ?? .distantPast).addingTimeInterval(s)
            // Half a second early counts, so a timer that fires a little early
            // (timers are coalesced) does not need a second wake-up.
            if next.timeIntervalSince(now) <= 0.5 { run.append(id); entries[id]?.lastRun = now }
        }
        return run
    }

    /// When the next interval widget is due, or nil when nothing is (closed,
    /// or only `on open` widgets).
    public func nextWakeup(after now: Date) -> Date? {
        guard isOpen else { return nil }
        var earliest: Date?
        for id in order {
            guard let e = entries[id], case .interval(let s) = e.policy else { continue }
            let next = e.lastRun.map { max(now, $0.addingTimeInterval(s)) } ?? now
            if earliest == nil || next < earliest! { earliest = next }
        }
        return earliest
    }

    /// Marks a widget to run on the next `due` or open (after its file changed,
    /// or when it was clicked).
    public func invalidate(_ id: String) {
        entries[id]?.lastRun = nil
    }
}
