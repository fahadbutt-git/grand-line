import SwiftUI
import IcebergKit

/// MotionSpec as SwiftUI animations. Each takes Reduce Motion and returns
/// a short cross-fade instead of the spring.
enum Motion {
    static func spring(_ spec: SpringSpec) -> Animation {
        .spring(response: spec.response, dampingFraction: spec.dampingFraction)
    }

    static func fade(_ reduceMotion: Bool, _ spec: SpringSpec) -> Animation {
        reduceMotion ? .easeOut(duration: MotionSpec.fadeDuration) : spring(spec)
    }

    static func open(reduceMotion: Bool) -> Animation { fade(reduceMotion, MotionSpec.open) }
    static func close(reduceMotion: Bool) -> Animation { fade(reduceMotion, MotionSpec.close) }
    static func wings(reduceMotion: Bool) -> Animation { fade(reduceMotion, MotionSpec.wings) }
    static func basket(reduceMotion: Bool) -> Animation { fade(reduceMotion, MotionSpec.basket) }
    static func drop(reduceMotion: Bool) -> Animation { fade(reduceMotion, MotionSpec.drop) }
    /// Values changing in place; nil (no animation) with Reduce Motion.
    static func content(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : spring(MotionSpec.content) }
    static let hover = Animation.easeOut(duration: MotionSpec.hoverDuration)
}

/// A surface coming into being: it fades in while growing from a little
/// smaller and sharpening from a blur, anchored where it comes from (the
/// notch for the panel, the pointer for the basket). It leaves along the
/// same path. With Reduce Motion it only fades.
struct Materialise: ViewModifier {
    /// 0 gone, 1 fully there.
    let progress: Double
    let anchor: UnitPoint
    let reduceMotion: Bool
    /// False when the window fades instead (the basket, whose shadow must go with it).
    var fades = true

    func body(content: Content) -> some View {
        let gone = 1 - progress
        content
            .opacity(fades ? progress : 1)
            .scaleEffect(reduceMotion ? 1 : 1 - (1 - MotionSpec.materialiseScale) * gone, anchor: anchor)
            .blur(radius: reduceMotion ? 0 : MotionSpec.materialiseBlur * gone)
    }
}

extension AnyTransition {
    static func materialise(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        .modifier(active: Materialise(progress: 0, anchor: anchor, reduceMotion: reduceMotion),
                  identity: Materialise(progress: 1, anchor: anchor, reduceMotion: reduceMotion))
    }
}
