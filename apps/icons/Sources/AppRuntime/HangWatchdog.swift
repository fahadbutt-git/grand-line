import Foundation

/// When the watchdog runs: while the app is in front, and for a short while
/// after the person last used it (a menu-bar app is rarely "active", but its
/// panel is in use right after the shortcut). Otherwise it is off, so an app
/// left alone costs nothing.
public struct WatchWindow: Equatable, Sendable {
    /// How long after the last use it keeps watching.
    public static let afterUse: TimeInterval = 30

    public static func isWatching(active: Bool, lastUse: Date?, now: Date) -> Bool {
        if active { return true }
        guard let lastUse else { return false }
        let since = now.timeIntervalSince(lastUse)
        return since >= 0 && since < afterUse
    }
}

/// What a ping that came back late says.
public enum StallReport {
    /// Stalls shorter than this are not written down.
    public static let threshold: TimeInterval = 0.25

    /// The log line for a ping answered `delay` seconds late, or nil.
    public static func line(delay: TimeInterval) -> String? {
        guard delay >= threshold else { return nil }
        return "main thread stalled \(Int((delay * 1000).rounded())) ms"
    }

    /// The longest stall in a log's text, in milliseconds (the journeys use it).
    public static func longest(in text: String) -> Int {
        var best = 0
        for line in text.split(separator: "\n") {
            guard let range = line.range(of: "main thread stalled ") else { continue }
            let rest = line[range.upperBound...].prefix { $0.isNumber }
            best = max(best, Int(rest) ?? 0)
        }
        return best
    }
}

/// Notices the main thread not answering. Every two seconds, while the
/// window says to watch, a background timer (utility QoS, with half a second
/// of leeway) sends the main queue a ping; a ping answered 250 ms or more
/// late is written to the app's log with how long it waited. No stack is
/// taken, so it is cheap; and with the app unused the timer is cancelled,
/// so it never wakes the Mac.
public final class HangWatchdog: @unchecked Sendable {
    public static let interval: TimeInterval = 2

    private let log: AppLog
    private let queue = DispatchQueue(label: "AppRuntime.HangWatchdog", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var active = false
    private var lastUse: Date?
    private var waiting = false
    private var stopAt: DispatchWorkItem?

    public init(log: AppLog) {
        self.log = log
    }

    /// The app came to the front or left it.
    public func setActive(_ isActive: Bool) {
        lock.lock()
        active = isActive
        lock.unlock()
        update()
    }

    /// The person used the app (its panel opened): watch for a while.
    public func noteUse(at date: Date = Date()) {
        lock.lock()
        lastUse = date
        lock.unlock()
        update()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timer != nil
    }

    private func update() {
        let now = Date()
        lock.lock()
        let watch = WatchWindow.isWatching(active: active, lastUse: lastUse, now: now)
        let remaining = lastUse.map { WatchWindow.afterUse - now.timeIntervalSince($0) } ?? 0
        let isActive = active
        if watch, timer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(500))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            timer = t
        } else if !watch, let t = timer {
            t.cancel()
            timer = nil
        }
        stopAt?.cancel()
        stopAt = nil
        if watch, !isActive, remaining > 0 {
            // Off again once the window after the last use has passed.
            let item = DispatchWorkItem { [weak self] in self?.update() }
            stopAt = item
            queue.asyncAfter(deadline: .now() + remaining + 0.1, execute: item)
        }
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        guard !waiting else {
            lock.unlock()
            return
        }
        waiting = true
        lock.unlock()
        let sent = DispatchTime.now()
        DispatchQueue.main.async { [weak self] in
            let delay = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1_000_000_000
            guard let self else { return }
            self.lock.lock()
            self.waiting = false
            self.lock.unlock()
            if let line = StallReport.line(delay: delay) { self.log.write(line) }
        }
    }
}
