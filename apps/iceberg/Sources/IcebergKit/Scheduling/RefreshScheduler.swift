import Foundation

/// Decides when each user widget runs. It holds no timer: the app asks
/// `nextWakeup` and arms one timer for that moment, so nothing wakes the Mac
/// in between, and nothing at all while the panel is closed (unless a widget
/// asks for `updates = "always"`).
///
/// - `on open` widgets run each time the panel opens (at most once every
///   `onOpenThrottle` seconds, so brushing past the notch does not re-run them).
/// - Interval widgets run while the panel is open. When it opens, any whose
///   value is older than its interval runs at once; the rest keep their value.
///   Those with `whileClosed` also run while it is closed.
/// - While paused (sleep, Low Power Mode) only widgets with `ignoresPause`
///   run. `resumed` then names what was missed.
/// - A widget that keeps failing waits longer each time (`FailureBackoff`).
public final class RefreshScheduler {
    public static let onOpenThrottle: TimeInterval = 3

    /// One widget, as the scheduler sees it.
    public struct Spec: Equatable, Sendable {
        public var id: String
        public var policy: RefreshPolicy
        /// `updates = "always"`: interval runs go on while the panel is closed.
        public var whileClosed: Bool
        /// `always = true`: runs during sleep and Low Power Mode too.
        public var ignoresPause: Bool

        public init(id: String, policy: RefreshPolicy, whileClosed: Bool = false, ignoresPause: Bool = false) {
            self.id = id
            self.policy = policy
            self.whileClosed = whileClosed
            self.ignoresPause = ignoresPause
        }
    }

    struct Entry {
        var spec: Spec
        var lastRun: Date?
        var backoff = FailureBackoff()
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    public private(set) var isOpen = false
    /// When the panel last opened, so `resumed` knows which on-open runs were missed.
    private var openedAt: Date?
    /// Sleep or Low Power Mode: only `ignoresPause` widgets run.
    public var isPaused = false

    public init() {}

    /// Replaces the widget list. Widgets that stay, with the same policy, keep
    /// the time they last ran.
    public func setWidgets(_ widgets: [(id: String, policy: RefreshPolicy)]) {
        setWidgets(widgets.map { Spec(id: $0.id, policy: $0.policy) })
    }

    public func setWidgets(_ specs: [Spec]) {
        var next: [String: Entry] = [:]
        var nextOrder: [String] = []
        for s in specs where next[s.id] == nil {
            if let old = entries[s.id], old.spec.policy == s.policy {
                next[s.id] = Entry(spec: s, lastRun: old.lastRun, backoff: old.backoff)
            } else {
                next[s.id] = Entry(spec: s, lastRun: nil)
            }
            nextOrder.append(s.id)
        }
        entries = next
        order = nextOrder
    }

    public var widgetIDs: [String] { order }

    public func lastRun(of id: String) -> Date? { entries[id]?.lastRun }

    private func mayRun(_ e: Entry) -> Bool { !isPaused || e.spec.ignoresPause }

    /// The panel opened: the widgets to run now, already marked as run.
    public func panelOpened(at now: Date) -> [String] {
        isOpen = true
        openedAt = now
        var run: [String] = []
        for id in order {
            guard let e = entries[id], mayRun(e), !e.backoff.blocks(at: now) else { continue }
            let stale: Bool
            switch e.spec.policy {
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

    /// When an interval widget may next run: its interval after the last
    /// run, and not before its backoff ends.
    private func readyAt(_ e: Entry, interval s: TimeInterval) -> Date {
        let next = (e.lastRun ?? .distantPast).addingTimeInterval(s)
        if let wait = e.backoff.notBefore, wait > next { return wait }
        return next
    }

    private func counts(_ e: Entry) -> Bool { (isOpen || e.spec.whileClosed) && mayRun(e) }

    /// Interval widgets due at `now`, already marked as run. While closed,
    /// only those that run while closed.
    public func due(at now: Date) -> [String] {
        var run: [String] = []
        for id in order {
            guard let e = entries[id], case .interval(let s) = e.spec.policy, counts(e) else { continue }
            // Half a second early counts, so a timer that fires a little early
            // (timers are coalesced) does not need a second wake-up.
            if readyAt(e, interval: s).timeIntervalSince(now) <= 0.5 { run.append(id); entries[id]?.lastRun = now }
        }
        return run
    }

    /// When the next interval widget is due, or nil when nothing is (closed,
    /// paused, or only `on open` widgets).
    public func nextWakeup(after now: Date) -> Date? {
        var earliest: Date?
        for id in order {
            guard let e = entries[id], case .interval(let s) = e.spec.policy, counts(e) else { continue }
            let next = e.lastRun == nil && e.backoff.notBefore == nil ? now : max(now, readyAt(e, interval: s))
            if earliest == nil || next < earliest! { earliest = next }
        }
        return earliest
    }

    /// The pause ended (woke, or Low Power Mode went off): what was missed
    /// meanwhile, already marked as run.
    public func resumed(at now: Date) -> [String] {
        var run: [String] = []
        for id in order {
            guard let e = entries[id], counts(e), !e.backoff.blocks(at: now) else { continue }
            let missed: Bool
            switch e.spec.policy {
            case .onOpen:
                guard isOpen else { continue }
                missed = e.lastRun == nil || (openedAt.map { e.lastRun! < $0 } ?? false)
            case .interval(let s):
                missed = readyAt(e, interval: s).timeIntervalSince(now) <= 0.5
            }
            if missed { run.append(id); entries[id]?.lastRun = now }
        }
        return run
    }

    /// Marks a widget to run on the next `due` or open (after its file changed,
    /// or a signal came while the panel was closed).
    public func invalidate(_ id: String) {
        entries[id]?.lastRun = nil
    }

    /// Notes a run made outside the schedule (a signal, a click).
    public func markRun(_ id: String, at now: Date) {
        entries[id]?.lastRun = now
    }

    /// Notes how a run went; repeated failures push the next run back.
    public func record(_ id: String, success: Bool, at now: Date) {
        entries[id]?.backoff.record(success: success, at: now)
    }

    /// Forgets the failures (the file was edited, or the widget was clicked).
    public func resetBackoff(_ id: String) {
        entries[id]?.backoff.reset()
    }

    /// When a failing widget may run again, while that is still ahead.
    public func backoffUntil(_ id: String, at now: Date) -> Date? {
        guard let e = entries[id], e.backoff.blocks(at: now) else { return nil }
        return e.backoff.notBefore
    }

    /// True when a run asked for now (a signal) should wait: paused, or backing off.
    public func isHeldBack(_ id: String, at now: Date) -> Bool {
        guard let e = entries[id] else { return true }
        return !mayRun(e) || e.backoff.blocks(at: now)
    }
}
