import Foundation

/// The colour the closed notch's playing bars take from the artwork: the
/// strongest hue in a small copy of the cover, made light enough to read on
/// the black notch. Worked out once per track.
public enum ArtworkTint {
    /// The side of the copy the app draws the artwork into.
    public static let sampleSide = 24

    /// From premultiplied RGBA bytes (CoreGraphics' usual layout). Nil for a
    /// grey, black or white cover, so the caller uses the theme's accent.
    public static func dominant(rgba: [UInt8]) -> RGB? {
        let bins = 12
        var weight = [Double](repeating: 0, count: bins)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: bins)
        var counted = 0.0
        var i = 0
        while i + 3 < rgba.count {
            let a = Double(rgba[i + 3]) / 255
            defer { i += 4 }
            guard a > 0.5 else { continue }
            let r = Double(rgba[i]) / 255 / a, g = Double(rgba[i + 1]) / 255 / a, b = Double(rgba[i + 2]) / 255 / a
            counted += 1
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            guard saturation > 0.25, maxC > 0.18 else { continue }
            let hue = Self.hue(r, g, b, maxC: maxC, minC: minC)
            let bin = min(bins - 1, Int(hue * Double(bins)))
            let w = saturation * maxC
            weight[bin] += w
            sums[bin].0 += r * w
            sums[bin].1 += g * w
            sums[bin].2 += b * w
        }
        guard counted > 0, let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] / counted > 0.04 else { return nil }
        let w = weight[best]
        return RGB(red: min(1, sums[best].0 / w), green: min(1, sums[best].1 / w), blue: min(1, sums[best].2 / w))
    }

    static func hue(_ r: Double, _ g: Double, _ b: Double, maxC: Double, minC: Double) -> Double {
        let d = maxC - minC
        guard d > 0 else { return 0 }
        var h: Double
        if maxC == r { h = (g - b) / d }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// `color` lifted toward white just far enough to reach `ratio` on black.
    public static func readableOnBlack(_ color: RGB, ratio: Double = 4.5) -> RGB {
        let black = RGB(red: 0, green: 0, blue: 0)
        for step in 0...20 {
            let candidate = color.mixed(with: RGB(red: 1, green: 1, blue: 1), Double(step) / 20)
            if RGB.contrast(candidate, black) >= ratio { return candidate }
        }
        return RGB(red: 1, green: 1, blue: 1)
    }

    /// The bars' colour: the cover's, else the theme's accent, readable on black.
    public static func tint(cover: RGB?, accent: RGB) -> RGB {
        readableOnBlack(cover ?? accent)
    }
}

extension RGB {
    /// `amount` 0 keeps this colour, 1 gives `other`.
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount)
    }
}
