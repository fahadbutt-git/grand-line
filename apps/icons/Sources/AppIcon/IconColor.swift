import Foundation

/// An sRGB colour with components from 0 to 1.
public struct IconColor: Sendable, Hashable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// "0a6cd6" or "#0a6cd6".
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit), let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    public static let black = IconColor(red: 0, green: 0, blue: 0)
    public static let white = IconColor(red: 1, green: 1, blue: 1)

    /// Lowercase, without "#".
    public var hex: String {
        String(format: "%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    public var description: String { "#" + hex }

    /// `amount` 0 keeps this colour, 1 gives `other`.
    public func mixed(with other: IconColor, _ amount: Double) -> IconColor {
        IconColor(red: red + (other.red - red) * amount,
                  green: green + (other.green - green) * amount,
                  blue: blue + (other.blue - blue) * amount)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}
