import Foundation

/// A spring in Apple's two terms: how quickly it reaches its target
/// (`response`, seconds, not a duration) and how much it overshoots
/// (`dampingFraction`, 1 for none).
public struct SpringSpec: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }

    /// True when the spring overshoots its target.
    public var bounces: Bool { dampingFraction < 1 }
}

/// Every motion in Iceberg, in one place. Movement that merely appears (the
/// panel opening on hover, the wings, a HUD) is critically damped, so it
/// never overshoots. Only motion that carries the user's momentum, a file
/// thrown onto the shelf or into the basket, settles with a small bounce.
/// With Reduce Motion each becomes a short cross-fade.
public enum MotionSpec {
    /// The notch opening into the panel.
    public static let open = SpringSpec(response: 0.36, dampingFraction: 1)
    /// The panel closing back into the notch: the same path, a little quicker.
    public static let close = SpringSpec(response: 0.3, dampingFraction: 1)
    /// The wings beside the closed notch (music, HUDs).
    public static let wings = SpringSpec(response: 0.3, dampingFraction: 1)
    /// The drop basket appearing under the pointer and going again.
    public static let basket = SpringSpec(response: 0.28, dampingFraction: 1)
    /// A file dropped on the shelf or in the basket: the drag's momentum
    /// carries into a small settle.
    public static let drop = SpringSpec(response: 0.34, dampingFraction: 0.8)
    /// Values changing in place: a level, a number, a symbol.
    public static let content = SpringSpec(response: 0.24, dampingFraction: 1)
    /// A control let go after a press.
    public static let release = SpringSpec(response: 0.22, dampingFraction: 1)

    /// The press itself shows on mouse-down, this fast.
    public static let pressDuration: Double = 0.06
    /// Hover highlights.
    public static let hoverDuration: Double = 0.12
    /// What replaces each spring with Reduce Motion.
    public static let fadeDuration: Double = 0.14

    /// How far a pressed control shrinks.
    public static let pressedScale: Double = 0.92
    /// A surface materialising: it starts this much smaller and this
    /// blurred (points), and grows sharp as it fades in. It leaves the same way.
    public static let materialiseScale: Double = 0.94
    public static let materialiseBlur: Double = 8

    /// The window is fitted to the closed shape once the spring has
    /// finished. Should SwiftUI never say so (the window off screen), it is
    /// fitted after this long anyway; well past every spring above.
    public static let settleFallback: TimeInterval = 1.0
}
