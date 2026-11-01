import Foundation

/// What an app remembers about its runs, to tell a crash from a quit and to
/// stop a crash loop: when the current run started, whether the last one
/// ended cleanly, and the crashes of the last ten minutes.
public struct RunRecord: Codable, Equatable, Sendable {
    public var pid: Int32 = 0
    public var started: Date?
    /// Set as the app quits normally.
    public var cleanExit = true
    public var crashes: [Date] = []
    /// It stayed down after a crash loop (and said so once).
    public var stayedDown = false

    public init() {}

    /// Crashes this close together, this many times, and the app stays down.
    public static let loopWindow: TimeInterval = 10 * 60
    public static let loopCount = 3

    public enum Launch: Equatable, Sendable {
        case run
        /// The last run crashed: run, and write it down.
        case runAfterCrash(started: Date?)
        /// Too many crashes in a row: quit at once (cleanly, so nothing
        /// starts it again) and, the first time, say so.
        case stayDown(notify: Bool)
    }

    /// The app is starting: counts the last run if it crashed, and says
    /// whether to run.
    public mutating func launch(pid: Int32, at now: Date) -> Launch {
        let crashed = !cleanExit && started != nil
        if stayedDown && !crashed {
            // Opened again by hand after staying down: a fresh start.
            crashes = []
            stayedDown = false
        } else if crashed {
            crashes.append(started ?? now)
        }
        crashes = crashes.filter { now.timeIntervalSince($0) < Self.loopWindow }
        if crashes.count >= Self.loopCount {
            let notify = !stayedDown
            stayedDown = true
            cleanExit = true
            return .stayDown(notify: notify)
        }
        let previous = started
        self.pid = pid
        started = now
        cleanExit = false
        return crashed ? .runAfterCrash(started: previous) : .run
    }

    public mutating func quitCleanly() {
        cleanExit = true
    }
}

/// What a watcher (the index service, once a minute) does about an app that
/// is not running.
public enum RelaunchDecision: Equatable, Sendable {
    case nothing
    case relaunch

    /// Relaunch only an app that crashed: it had started, did not quit
    /// cleanly, is not running, and is not staying down after a loop.
    public static func decide(_ record: RunRecord?, alive: Bool) -> RelaunchDecision {
        guard let record, record.started != nil, !record.cleanExit, !record.stayedDown, !alive else { return .nothing }
        return .relaunch
    }
}

/// The run record on disk: `~/.local/state/grand-line-runtime/<name>.json`,
/// beside the package's state folder rather than in it (the apps watch that
/// folder for theme changes).
public final class CrashGuard: @unchecked Sendable {
    public let name: String
    public let url: URL
    private let log: AppLog
    private let lock = NSLock()

    public static func folder(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".local/state/grand-line-runtime", isDirectory: true)
    }

    public init(name: String, log: AppLog, home: String = NSHomeDirectory()) {
        self.name = name
        self.log = log
        url = CrashGuard.folder(home: home).appendingPathComponent("\(name).json")
    }

    public static func read(_ url: URL) -> RunRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(RunRecord.self, from: data)
    }

    public static func write(_ record: RunRecord, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(record) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Call first thing at launch. Returns false when the app should quit at
    /// once (a crash loop): it has written why, and posted one notice. With
    /// `staysDownAfterLoop` false (an app only ever opened by hand), or
    /// during the journeys, a loop is written down and the app runs anyway.
    @discardableResult
    public func launch(displayName: String, staysDownAfterLoop: Bool = true, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let pid = ProcessInfo.processInfo.processIdentifier
        var record = CrashGuard.read(url) ?? RunRecord()
        var decision = record.launch(pid: pid, at: now)
        let enforced = staysDownAfterLoop && ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1"
        if case .stayDown = decision, !enforced {
            log.write("\(RunRecord.loopCount) crashes within \(Int(RunRecord.loopWindow / 60)) minutes")
            record.stayedDown = false
            record.cleanExit = false
            record.pid = pid
            record.started = now
            decision = .run
        }
        CrashGuard.write(record, to: url)
        switch decision {
        case .run:
            return true
        case .runAfterCrash(let started):
            let when = started.map { ISO8601DateFormatter().string(from: $0) } ?? "an earlier run"
            log.write("the last run (started \(when)) ended unexpectedly; started again")
            return true
        case .stayDown(let notify):
            log.write("\(RunRecord.loopCount) crashes within \(Int(RunRecord.loopWindow / 60)) minutes; staying closed")
            if notify {
                QuietNotice.post(title: "\(displayName) stopped",
                                 message: "It closed unexpectedly \(RunRecord.loopCount) times, so it stays closed. Open it again when you need it.")
            }
            log.flush()
            return false
        }
    }

    /// Call as the app quits normally.
    public func quitCleanly() {
        lock.lock()
        defer { lock.unlock() }
        guard var record = CrashGuard.read(url) else { return }
        record.quitCleanly()
        CrashGuard.write(record, to: url)
    }
}

/// "This app is in the middle of something": a file the unattended update
/// reads before it swaps an app (lib/auto-update.sh, update_swap_decision).
/// It lives in the runtime folder and names the app's process, so one left
/// behind by a crash does not count.
public final class BusyMarker: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "AppRuntime.BusyMarker", qos: .utility)
    private var reasons: Set<String> = []

    public init(name: String, home: String = NSHomeDirectory()) {
        url = CrashGuard.folder(home: home).appendingPathComponent("\(name).busy")
    }

    public func set(_ reason: String, busy: Bool) {
        lock.lock()
        let before = !reasons.isEmpty
        if busy { reasons.insert(reason) } else { reasons.remove(reason) }
        let after = !reasons.isEmpty
        lock.unlock()
        guard before != after else { return }
        let url = self.url
        let pid = ProcessInfo.processInfo.processIdentifier
        queue.async {
            if after {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? "\(pid)\n".write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
