import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// How a floating surface (the drop basket) is drawn, from the macOS
/// accessibility display options. Normally a translucent material with the
/// theme's panel colour laid over it and a hairline edge. Reduce
/// Transparency makes it solid. Increase Contrast makes it solid with a
/// defined edge that leans towards the text colour.
public struct SurfaceStyle: Equatable, Sendable {
    /// Draw the blurred material behind the theme's colour.
    public var usesMaterial: Bool
    /// The theme's panel colour over the material (1 is solid).
    public var tintOpacity: Double
    /// How far the edge moves from the theme's line colour towards its text colour.
    public var edgeEmphasis: Double
    /// The edge's width in device pixels.
    public var edgePixels: Int

    public init(usesMaterial: Bool, tintOpacity: Double, edgeEmphasis: Double, edgePixels: Int) {
        self.usesMaterial = usesMaterial
        self.tintOpacity = tintOpacity
        self.edgeEmphasis = edgeEmphasis
        self.edgePixels = edgePixels
    }

    public static func resolve(reduceTransparency: Bool, increaseContrast: Bool) -> SurfaceStyle {
        if increaseContrast {
            return SurfaceStyle(usesMaterial: false, tintOpacity: 1, edgeEmphasis: 0.5, edgePixels: 2)
        }
        if reduceTransparency {
            return SurfaceStyle(usesMaterial: false, tintOpacity: 1, edgeEmphasis: 0, edgePixels: 1)
        }
        return SurfaceStyle(usesMaterial: true, tintOpacity: 0.62, edgeEmphasis: 0, edgePixels: 1)
    }

    /// Lines inside the panel (dividers, chip edges): with Increase
    /// Contrast they lean this far towards the text colour.
    public static func lineEmphasis(increaseContrast: Bool) -> Double {
        increaseContrast ? 0.45 : 0
    }
}

/// Keeps lines and edges on whole device pixels, so a hairline is one
/// crisp pixel on a Retina display and on a standard one.
public enum PixelGrid {
    /// One device pixel, in points.
    public static func hairline(scale: CGFloat) -> CGFloat {
        1 / max(1, scale)
    }

    /// `pixels` device pixels, in points.
    public static func width(pixels: Int, scale: CGFloat) -> CGFloat {
        CGFloat(max(0, pixels)) / max(1, scale)
    }

    /// The nearest point on the pixel grid.
    public static func align(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let s = max(1, scale)
        return (value * s).rounded() / s
    }

    /// The largest pixel-aligned length not above `value`.
    public static func floor(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let s = max(1, scale)
        return (value * s).rounded(.down) / s
    }
}
