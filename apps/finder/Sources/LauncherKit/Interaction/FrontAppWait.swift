import Foundation

/// When an action that types, pastes or presses a menu item in the app that
/// was in front may run: at once when that app is already active (the search
/// window has gone, so the keys reach it), else when macOS says it became
/// active, with a short safety limit so the action never waits on an app
/// that does not answer.
public enum FrontAppWait: Equatable, Sendable {
    /// No app to wait for, or it is already in front.
    case now
    /// Wait for that app's activation, at most `limit` seconds.
    case activation(limit: TimeInterval)

    /// The safety limit: long enough for a busy app to come forward, short
    /// enough that the action still feels immediate when it does not.
    public static let limit: TimeInterval = 0.5

    public static func plan(hasApp: Bool, isActive: Bool, isTerminated: Bool) -> FrontAppWait {
        guard hasApp, !isTerminated, !isActive else { return .now }
        return .activation(limit: limit)
    }
}

/// Work that runs once, whichever of its triggers comes first (the app's
/// activation, the safety limit); later triggers do nothing.
public final class OnceWork {
    private var work: (() -> Void)?

    public init(_ work: @escaping () -> Void) { self.work = work }

    public var isDone: Bool { work == nil }

    public func run() {
        guard let work else { return }
        self.work = nil
        work()
    }

    /// Drops the work without running it (a newer action replaced it).
    public func cancel() { work = nil }
}
