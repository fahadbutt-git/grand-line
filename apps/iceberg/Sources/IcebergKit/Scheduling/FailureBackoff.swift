import Foundation

/// How long a widget that keeps failing waits before its next run. One
/// failure changes nothing (a network blip); after that the wait doubles
/// from `base` up to `maximum`, and one success clears it. A status page
/// that is down is then asked a few times an hour, not every few seconds.
public struct FailureBackoff: Equatable, Sendable {
    public static let base: TimeInterval = 10
    public static let maximum: TimeInterval = 30 * 60
    /// The first wait before a stream that ended is started again.
    public static let streamBase: TimeInterval = 2

    public private(set) var failures = 0
    public private(set) var notBefore: Date?

    public init() {}

    /// The wait after `n` failures in a row: 0, 0, 10, 20, 40 ... seconds, at most 30 minutes.
    public static func delay(afterFailures n: Int) -> TimeInterval {
        guard n >= 2 else { return 0 }
        return min(maximum, base * pow(2, Double(min(n - 2, 20))))
    }

    /// The wait before restarting a stream that ended `n` times in a row:
    /// 2, 4, 8 ... seconds, at most 30 minutes.
    public static func streamDelay(afterFailures n: Int) -> TimeInterval {
        min(maximum, streamBase * pow(2, Double(min(max(n, 1) - 1, 20))))
    }

    public mutating func record(success: Bool, at now: Date) {
        if success { reset(); return }
        failures += 1
        let wait = Self.delay(afterFailures: failures)
        notBefore = wait > 0 ? now.addingTimeInterval(wait) : nil
    }

    public mutating func reset() {
        failures = 0
        notBefore = nil
    }

    /// True while the wait is still ahead (half a second early counts as over).
    public func blocks(at now: Date) -> Bool {
        notBefore.map { $0.timeIntervalSince(now) > 0.5 } ?? false
    }
}

/// Whether widget commands may run now. During sleep and in Low Power Mode
/// only widgets with `always = true` run; the rest wait and catch up after.
public struct ResourceGate: Equatable, Sendable {
    /// Between NSWorkspace's willSleep and didWake.
    public var asleep = false
    /// ProcessInfo.isLowPowerModeEnabled.
    public var lowPower = false

    public init(asleep: Bool = false, lowPower: Bool = false) {
        self.asleep = asleep
        self.lowPower = lowPower
    }

    public var isPaused: Bool { asleep || lowPower }

    public func allows(always: Bool) -> Bool { always || !isPaused }

    /// Why widgets are paused, for Settings; nil when they are not.
    public var reason: String? {
        if asleep { return "The Mac is asleep" }
        if lowPower { return "Low Power Mode is on" }
        return nil
    }
}
