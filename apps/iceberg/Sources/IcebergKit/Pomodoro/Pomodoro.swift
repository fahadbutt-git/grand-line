import Foundation

/// The Pomodoro timer's three phases.
public enum PomodoroPhase: String, Codable, Sendable, CaseIterable {
    case focus
    case shortBreak = "short_break"
    case longBreak = "long_break"

    /// "Focus", "Short break", "Long break".
    public var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    public var isBreak: Bool { self != .focus }
}

/// Whether the timer runs.
public enum PomodoroStatus: String, Codable, Sendable {
    /// Waiting to start the phase it shows.
    case idle
    case running
    case paused
}

/// The lengths and rules, from iceberg.toml (`pomodoro_*`).
public struct PomodoroConfig: Equatable, Sendable {
    /// Minutes.
    public var focus: Int
    public var shortBreak: Int
    public var longBreak: Int
    /// Focus rounds before a long break.
    public var rounds: Int
    /// The next phase starts by itself when one ends.
    public var autoStart: Bool
    /// A sound with the notice at a phase's end.
    public var sound: Bool

    public static let focusRange = 1...180
    public static let shortBreakRange = 1...60
    public static let longBreakRange = 1...120
    public static let roundsRange = 1...12
    /// The lengths the panel offers (minutes), and its step.
    public static let presets = [15, 25, 45, 50]
    public static let step = 5

    public init(focus: Int = 25, shortBreak: Int = 5, longBreak: Int = 15, rounds: Int = 4,
                autoStart: Bool = false, sound: Bool = true) {
        self.focus = Self.clamp(focus, Self.focusRange)
        self.shortBreak = Self.clamp(shortBreak, Self.shortBreakRange)
        self.longBreak = Self.clamp(longBreak, Self.longBreakRange)
        self.rounds = Self.clamp(rounds, Self.roundsRange)
        self.autoStart = autoStart
        self.sound = sound
    }

    public init(settings: IcebergSettings) {
        self.init(focus: settings.pomodoroFocus, shortBreak: settings.pomodoroShortBreak,
                  longBreak: settings.pomodoroLongBreak, rounds: settings.pomodoroRounds,
                  autoStart: settings.pomodoroAutoStart, sound: settings.pomodoroSound)
    }

    public func minutes(of phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }

    public func length(of phase: PomodoroPhase) -> TimeInterval { TimeInterval(minutes(of: phase) * 60) }

    /// The focus length one step (5 minutes) up or down, kept in range.
    public func focus(steppedBy steps: Int) -> Int {
        Self.clamp(focus + steps * Self.step, Self.focusRange)
    }

    static func clamp(_ n: Int, _ range: ClosedRange<Int>) -> Int { min(max(n, range.lowerBound), range.upperBound) }
}

/// A phase that ended, for the notice and the notch.
public struct PomodoroPhaseEnd: Equatable, Sendable {
    public var finished: PomodoroPhase
    public var next: PomodoroPhase
    /// The next phase's length in minutes.
    public var nextMinutes: Int
    /// When it ended (the planned end, not when it was noticed).
    public var at: Date
    /// The next phase started by itself (`pomodoro_auto_start`).
    public var nextStarted: Bool
    /// Ended with Skip rather than by running out: no notice.
    public var skipped: Bool

    /// The notice's title: "Focus done", "Break over".
    public var title: String {
        finished == .focus ? "Focus done" : "Break over"
    }

    /// The notice's text: "Take a 5 min break." or "Focus for 25 min."
    public var body: String {
        switch next {
        case .shortBreak:
            return nextStarted ? "Your \(nextMinutes) min break has started." : "Take a \(nextMinutes) min break."
        case .longBreak:
            return nextStarted ? "Your \(nextMinutes) min long break has started." : "Take a \(nextMinutes) min long break."
        case .focus:
            return nextStarted ? "Focus for \(nextMinutes) min has started." : "Time to focus for \(nextMinutes) min."
        }
    }

    /// A notice for an end seen long after it happened (asleep, or Iceberg
    /// not running) would be stale; only ends within this many seconds are announced.
    public static let announceWithin: TimeInterval = 10 * 60

    public func shouldAnnounce(at now: Date) -> Bool {
        !skipped && now.timeIntervalSince(at) <= Self.announceWithin
    }
}

/// The Pomodoro timer as data: the phase, whether it runs, and when the
/// phase ends. It keeps the end date, never a ticking count, so the time
/// left is worked out from the clock whenever it is shown, after sleep and
/// after a restart alike. `update(at:config:)` moves it past every phase
/// end that has passed.
public struct PomodoroTimer: Equatable, Sendable, Codable {
    public private(set) var phase: PomodoroPhase
    public private(set) var status: PomodoroStatus
    /// The current phase's whole length, in seconds.
    public private(set) var length: TimeInterval
    /// When the phase ends, while it runs.
    public private(set) var endsAt: Date?
    /// The time left while paused or idle.
    public private(set) var remainingWhenStopped: TimeInterval
    /// Focus rounds done since the last long break.
    public private(set) var completed: Int
    /// Focus rounds before a long break (from the config, kept for the dots).
    public private(set) var rounds: Int

    public init(config: PomodoroConfig = PomodoroConfig()) {
        phase = .focus
        status = .idle
        length = config.length(of: .focus)
        endsAt = nil
        remainingWhenStopped = length
        completed = 0
        rounds = config.rounds
    }

    enum CodingKeys: String, CodingKey {
        case phase, status, length, completed, rounds
        case endsAt = "ends_at"
        case remainingWhenStopped = "remaining"
    }

    /// Seconds left in this phase, never below zero.
    public func remaining(at now: Date) -> TimeInterval {
        if status == .running, let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return max(0, remainingWhenStopped)
    }

    /// The time left as the clock shows it, "24:59": whole seconds rounded
    /// up, so a new phase shows its full length and the end shows 0:00.
    public func clock(at now: Date) -> String { Self.clock(remaining(at: now)) }

    public static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The time left in words, for VoiceOver: "24 minutes 59 seconds".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let m = s / 60, r = s % 60
        let minutes = m == 1 ? "1 minute" : "\(m) minutes"
        let secs = r == 1 ? "1 second" : "\(r) seconds"
        if m == 0 { return secs }
        return r == 0 ? minutes : "\(minutes) \(secs)"
    }

    /// Running or paused: what the closed notch shows.
    public var isActive: Bool { status != .idle }

    /// Nothing to reset: a fresh first focus round.
    public func isFresh(config: PomodoroConfig) -> Bool {
        status == .idle && phase == .focus && completed == 0 && remainingWhenStopped == config.length(of: .focus)
    }

    /// The round shown, 1-based: the focus round running, or the one done before this break.
    public var round: Int {
        phase == .focus ? min(completed + 1, rounds) : max(1, completed)
    }

    /// The dots under the time: which are done (`true`), in order.
    public var dots: [Bool] {
        (0..<rounds).map { $0 < completed }
    }

    // MARK: Changes

    /// Starts the phase shown, or resumes a paused one. With `minutes`, a
    /// focus round of that length starts now, whatever was running.
    public mutating func start(at now: Date, config: PomodoroConfig, minutes: Int? = nil) {
        if let minutes {
            let m = PomodoroConfig.clamp(minutes, PomodoroConfig.focusRange)
            phase = .focus
            length = TimeInterval(m * 60)
            run(for: length, from: now)
            return
        }
        switch status {
        case .running: return
        case .paused: resume(at: now)
        case .idle: run(for: remainingWhenStopped > 0 ? remainingWhenStopped : length, from: now)
        }
    }

    public mutating func pause(at now: Date) {
        guard status == .running else { return }
        remainingWhenStopped = remaining(at: now)
        endsAt = nil
        status = .paused
    }

    public mutating func resume(at now: Date) {
        guard status == .paused else { return }
        run(for: remainingWhenStopped, from: now)
    }

    /// Start when idle, pause when running, resume when paused (Caps + P).
    public mutating func toggle(at now: Date, config: PomodoroConfig) {
        switch status {
        case .idle: start(at: now, config: config)
        case .running: pause(at: now)
        case .paused: resume(at: now)
        }
    }

    /// Back to the first focus round, not running.
    public mutating func reset(config: PomodoroConfig) {
        self = PomodoroTimer(config: config)
    }

    /// Ends this phase now and moves to the next, as if it had run out
    /// (a skipped focus round counts). Running carries on running; idle or
    /// paused waits, unless `pomodoro_auto_start` is on.
    @discardableResult
    public mutating func skip(at now: Date, config: PomodoroConfig) -> PomodoroPhaseEnd {
        let wasRunning = status == .running
        let startNext = wasRunning || config.autoStart
        return advance(endedAt: now, startNext: startNext, from: now, config: config, skipped: true)
    }

    /// Moves past every phase end up to `now`. Returns them, oldest first.
    /// With auto-start, each next phase starts at the planned end of the one
    /// before, so a Mac that slept through several phases wakes in the
    /// right one; without it the timer waits at the next phase.
    @discardableResult
    public mutating func update(at now: Date, config: PomodoroConfig) -> [PomodoroPhaseEnd] {
        var ends: [PomodoroPhaseEnd] = []
        // A day of phases at most, so a clock set far ahead cannot spin.
        var guardCount = 0
        while status == .running, let end = endsAt, end <= now, guardCount < 500 {
            guardCount += 1
            ends.append(advance(endedAt: end, startNext: config.autoStart, from: end, config: config, skipped: false))
        }
        if status == .running, let end = endsAt, end <= now {
            // Still behind after the cap: wait at the next phase.
            remainingWhenStopped = length
            endsAt = nil
            status = .idle
        }
        return ends
    }

    /// The settings changed. Lengths of later phases follow by themselves;
    /// the current phase takes a new length for its own phase, keeping the
    /// time it has run (so 25 to 45 minutes, ten minutes in, leaves 35).
    public mutating func apply(_ config: PomodoroConfig, previous: PomodoroConfig?, at now: Date) {
        rounds = config.rounds
        if completed > rounds { completed = rounds }
        let newLength = config.length(of: phase)
        if let previous {
            guard previous.length(of: phase) != newLength else { return }
        } else {
            // The first settings after a restart: only a phase not yet begun follows them.
            guard newLength != length, status == .idle, remainingWhenStopped == length else { return }
        }
        setLength(newLength, at: now)
    }

    /// A new length for the current phase, keeping the time it has run.
    public mutating func setLength(_ newLength: TimeInterval, at now: Date) {
        let elapsed = max(0, length - remaining(at: now))
        length = max(60, newLength)
        let left = max(0, length - elapsed)
        switch status {
        case .running: endsAt = now.addingTimeInterval(left)
        case .paused, .idle: remainingWhenStopped = left
        }
    }

    private mutating func run(for seconds: TimeInterval, from now: Date) {
        endsAt = now.addingTimeInterval(max(0, seconds))
        remainingWhenStopped = max(0, seconds)
        status = .running
    }

    private mutating func advance(endedAt end: Date, startNext: Bool, from start: Date, config: PomodoroConfig,
                                  skipped: Bool) -> PomodoroPhaseEnd {
        let finished = phase
        let next: PomodoroPhase
        switch finished {
        case .focus:
            completed = min(completed + 1, config.rounds)
            next = completed >= config.rounds ? .longBreak : .shortBreak
        case .shortBreak:
            next = .focus
        case .longBreak:
            completed = 0
            next = .focus
        }
        rounds = config.rounds
        phase = next
        length = config.length(of: next)
        if startNext {
            run(for: length, from: start)
        } else {
            endsAt = nil
            remainingWhenStopped = length
            status = .idle
        }
        return PomodoroPhaseEnd(finished: finished, next: next, nextMinutes: config.minutes(of: next), at: end,
                                nextStarted: startNext, skipped: skipped)
    }

    // MARK: The state file

    /// `~/.local/state/grand-line/iceberg/pomodoro.json`: the timer, so a
    /// running one carries on after Iceberg restarts, and `iceberg pomodoro
    /// status` can read it. Dates are seconds since 1970.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> PomodoroTimer? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard var timer = try? decoder.decode(PomodoroTimer.self, from: data) else { return nil }
        // A file edited by hand stays within sense.
        timer.length = min(max(timer.length, 60), TimeInterval(PomodoroConfig.focusRange.upperBound * 60))
        timer.remainingWhenStopped = min(max(0, timer.remainingWhenStopped), timer.length)
        timer.rounds = PomodoroConfig.clamp(timer.rounds, PomodoroConfig.roundsRange)
        timer.completed = min(max(0, timer.completed), timer.rounds)
        if timer.status == .running && timer.endsAt == nil { timer.status = .paused }
        if timer.status != .running { timer.endsAt = nil }
        return timer
    }

    public static func load(from url: URL, config: PomodoroConfig) -> PomodoroTimer {
        guard let data = try? Data(contentsOf: url), data.count < 64 * 1024, let timer = decode(data) else {
            return PomodoroTimer(config: config)
        }
        return timer
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded().write(to: url, options: .atomic)
    }
}

/// What `iceberg pomodoro ...` and `iceberg://pomodoro/...` ask for.
public enum PomodoroCommand: Equatable, Sendable {
    /// Start, or resume; with minutes, a focus round of that length now.
    case start(minutes: Int?)
    case pause, resume, toggle, reset, skip

    /// From the action word and the optional minutes ("start", "25").
    /// Minutes must be a whole number from 1 to 180.
    public static func parse(action: String, minutes: String? = nil) -> PomodoroCommand? {
        switch action.lowercased() {
        case "start":
            guard let minutes, !minutes.isEmpty else { return .start(minutes: nil) }
            guard let m = Int(minutes), PomodoroConfig.focusRange.contains(m) else { return nil }
            return .start(minutes: m)
        case "pause": return minutes == nil ? .pause : nil
        case "resume": return minutes == nil ? .resume : nil
        case "toggle": return minutes == nil ? .toggle : nil
        case "reset", "stop": return minutes == nil ? .reset : nil
        case "skip", "next": return minutes == nil ? .skip : nil
        default: return nil
        }
    }

    /// Applies it to the timer. Returns the phase end a skip makes.
    @discardableResult
    public func apply(to timer: inout PomodoroTimer, at now: Date, config: PomodoroConfig) -> PomodoroPhaseEnd? {
        switch self {
        case .start(let minutes): timer.start(at: now, config: config, minutes: minutes)
        case .pause: timer.pause(at: now)
        case .resume: timer.resume(at: now)
        case .toggle: timer.toggle(at: now, config: config)
        case .reset: timer.reset(config: config)
        case .skip: return timer.skip(at: now, config: config)
        }
        return nil
    }
}

extension HUDEvent {
    /// The notch's short pulse at a phase's end: what comes next.
    public static func pomodoro(_ end: PomodoroPhaseEnd) -> HUDEvent {
        let symbol = end.next.isBreak ? "cup.and.saucer.fill" : "timer"
        let text = end.next.isBreak ? "Break" : "Focus"
        return HUDEvent(kind: .timer, symbol: symbol, level: nil, text: text,
                        label: "\(end.title). \(end.body)", tone: end.next.isBreak ? .good : .normal)
    }
}
