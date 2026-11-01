import Foundation

/// Tells a shake of the pointer (quick left-right reversals) from ordinary
/// movement, from the points of one drag. It is fed only while a file is
/// being dragged, from the mouse-dragged events macOS sends then, so it
/// costs nothing the rest of the time.
public struct ShakeDetector: Equatable, Sendable {
    /// The least sideways travel between two reversals, in points.
    public var minTravel: Double
    /// Reversals that count as a shake...
    public var reversals: Int
    /// ...within this many seconds.
    public var window: TimeInterval
    /// After a shake, the next one is heard only after this long.
    public var cooldown: TimeInterval

    private var extreme: Double?
    private var direction = 0
    private var turns: [TimeInterval] = []
    private var lastTime: TimeInterval?
    private var lastShake: TimeInterval?

    public init(minTravel: Double = 28, reversals: Int = 4, window: TimeInterval = 0.8, cooldown: TimeInterval = 1.0) {
        self.minTravel = minTravel
        self.reversals = reversals
        self.window = window
        self.cooldown = cooldown
    }

    /// A new drag: forget the movement so far (the cooldown stays).
    public mutating func reset() {
        extreme = nil
        direction = 0
        turns = []
        lastTime = nil
    }

    /// One pointer position (its x, in points) at time `t` (seconds).
    /// Returns true when this point completes a shake.
    public mutating func add(x: Double, at t: TimeInterval) -> Bool {
        if let last = lastTime, t - last > window { reset() }
        lastTime = t
        guard let ex = extreme else {
            extreme = x
            return false
        }
        if direction == 0 {
            if abs(x - ex) >= minTravel {
                direction = x > ex ? 1 : -1
                extreme = x
            }
            return false
        }
        // Further the same way: the turning point moves along.
        if (x - ex) * Double(direction) >= 0 {
            extreme = x
            return false
        }
        // Back the other way, but not far enough yet to count.
        guard abs(x - ex) >= minTravel else { return false }
        direction = -direction
        extreme = x
        turns.append(t)
        turns.removeAll { t - $0 > window }
        guard turns.count >= reversals else { return false }
        if let lastShake, t - lastShake < cooldown { return false }
        lastShake = t
        turns.removeAll()
        return true
    }
}

/// Follows the left mouse button to tell when a file is being dragged in
/// any app. macOS writes what is dragged to the drag pasteboard as the drag
/// starts, so its change count moving between the button going down and
/// the pointer being dragged means a drag began; its types say whether it
/// carries files.
///
/// The pasteboard is read only from the first dragged events after a press
/// (at most `maxChecks` of them); a drag that is not a file drag (a window,
/// a text selection) is settled once and costs nothing more.
public struct DragSessionTracker: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// No button down, or a drag that carries no files.
        case idle
        /// The button is down; not known yet whether files are dragged.
        case pressed
        /// Files are being dragged.
        case fileDrag
        /// Something other than files is dragged, or nothing is.
        case other
    }

    /// What one event means for the app.
    public enum Change: Equatable, Sendable {
        case none
        /// A file drag started.
        case began
        /// The pointer moved during a file drag.
        case moved
        /// The file drag ended (the button went up).
        case ended
    }

    public static let maxChecks = 40

    public private(set) var phase: Phase = .idle
    private var downCount: Int?
    private var checks = 0

    public init() {}

    public var isFileDrag: Bool { phase == .fileDrag }

    /// The button went down; `changeCount` is the drag pasteboard's now.
    public mutating func mouseDown(changeCount: Int) -> Change {
        let wasDragging = phase == .fileDrag
        phase = .pressed
        downCount = changeCount
        checks = 0
        return wasDragging ? .ended : .none
    }

    /// The pointer was dragged. `changeCount` is read each time until the
    /// drag is known; `hasFiles` only once it has changed.
    public mutating func dragged(changeCount: () -> Int, hasFiles: () -> Bool) -> Change {
        switch phase {
        case .fileDrag: return .moved
        case .idle, .other: return .none
        case .pressed:
            guard let down = downCount else { phase = .other; return .none }
            checks += 1
            if changeCount() != down {
                phase = hasFiles() ? .fileDrag : .other
                return phase == .fileDrag ? .began : .none
            }
            if checks >= Self.maxChecks { phase = .other }
            return .none
        }
    }

    /// The button went up.
    public mutating func mouseUp() -> Change {
        let was = phase
        phase = .idle
        downCount = nil
        checks = 0
        return was == .fileDrag ? .ended : .none
    }
}
