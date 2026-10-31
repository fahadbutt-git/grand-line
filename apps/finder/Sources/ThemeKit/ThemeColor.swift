import Foundation

/// An sRGB colour with components from 0 to 1.
public struct ThemeColor: Sendable, Hashable, CustomStringConvertible {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// "0a6cd6" or "#0a6cd6".
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let black = ThemeColor(red: 0, green: 0, blue: 0)

    /// Lowercase, without "#".
    public var hex: String {
        String(format: "%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public var description: String { "#" + hex }

    /// `amount` 0 keeps this colour, 1 gives `other`.
    public func mixed(with other: ThemeColor, _ amount: Double) -> ThemeColor {
        ThemeColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 to 21.
    public func contrast(with other: ThemeColor) -> Double {
        let a = luminance
        let b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// This colour moved toward `target` (then toward black or white) just far
    /// enough to reach `ratio` against every background.
    public func ensuringContrast(_ ratio: Double, against backgrounds: [ThemeColor], toward target: ThemeColor) -> ThemeColor {
        func passes(_ color: ThemeColor) -> Bool {
            backgrounds.allSatisfy { color.contrast(with: $0) >= ratio }
        }
        if passes(self) { return self }
        for step in 1...20 {
            let candidate = mixed(with: target, Double(step) / 20)
            if passes(candidate) { return candidate }
        }
        let darkBackground = (backgrounds.first?.luminance ?? 0) < 0.4
        let extreme: ThemeColor = darkBackground ? .white : .black
        for step in 1...20 {
            let candidate = target.mixed(with: extreme, Double(step) / 20)
            if passes(candidate) { return candidate }
        }
        return extreme
    }
}
