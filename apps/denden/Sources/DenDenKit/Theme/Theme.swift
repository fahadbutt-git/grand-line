import Foundation

/// A colour as three 0...1 components.
public struct RGB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// "1c1c1e", "#1c1c1e" or "#fff".
    public init?(hex raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        red = Double((v >> 16) & 0xFF) / 255
        green = Double((v >> 8) & 0xFF) / 255
        blue = Double(v & 0xFF) / 255
    }

    public var hex: String {
        func byte(_ c: Double) -> String {
            let b = String(Int((c * 255).rounded()), radix: 16)
            return b.count == 1 ? "0" + b : b
        }
        return byte(red) + byte(green) + byte(blue)
    }

    public var description: String { "#" + hex }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colours (1...21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (a.luminance, b.luminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

/// The package theme, read from `config/themes/<name>.theme`.
public struct Theme: Equatable, Sendable {
    public enum Mode: String, Sendable { case dark, light }

    public var name: String
    public var label: String
    public var mode: Mode
    /// TERM_BG: the background of every surface.
    public var background: RGB
    /// TERM_FG: text.
    public var foreground: RGB
    /// TERM_SELECTION: selected and hovered rows.
    public var selection: RGB
    /// HIGHLIGHT: the focused item and matches.
    public var highlight: RGB
    /// MUTED: secondary text.
    public var muted: RGB
    /// ACCENT_HEX: the accent colour.
    public var accent: RGB
    public var backgroundLighter: RGB
    public var backgroundDarker: RGB
    /// The 16 terminal colours.
    public var palette: [RGB]

    public func color(_ name: ThemeColorName) -> RGB {
        switch name {
        case .foreground: return foreground
        case .muted: return muted
        case .highlight: return highlight
        case .accent: return accent
        case .red: return paletteColor(1)
        case .green: return paletteColor(2)
        case .yellow: return paletteColor(3)
        case .blue: return paletteColor(4)
        case .magenta: return paletteColor(5)
        case .cyan: return paletteColor(6)
        }
    }

    public func resolve(_ widgetColor: WidgetColor) -> RGB {
        switch widgetColor {
        case .theme(let name): return self.color(name)
        case .hex(let rgb): return rgb
        }
    }

    func paletteColor(_ index: Int) -> RGB {
        index < palette.count ? palette[index] : foreground
    }

    /// The fields a theme file must have for Den Den.
    public static let requiredKeys = ["LABEL", "MODE", "TERM_BG", "TERM_FG", "TERM_SELECTION", "PALETTE",
                                      "ACCENT_HEX", "MUTED", "BG_LIGHTER", "BG_DARKER", "HIGHLIGHT"]

    /// Apple's dark greys (graphite.theme), used when no theme can be read.
    public static let graphite = Theme(
        name: "graphite", label: "Graphite", mode: .dark,
        background: RGB(hex: "1c1c1e")!, foreground: RGB(hex: "e5e5e7")!, selection: RGB(hex: "3a3a3c")!,
        highlight: RGB(hex: "409cff")!, muted: RGB(hex: "8e8e93")!, accent: RGB(hex: "98989d")!,
        backgroundLighter: RGB(hex: "2c2c2e")!, backgroundDarker: RGB(hex: "141416")!,
        palette: "2c2c2e ff453a 32d74b ffd60a 0a84ff bf5af2 64d2ff e5e5e7 636366 ff6961 30db5b ffd426 409cff da8fff 70d7ff ffffff"
            .split(separator: " ").map { RGB(hex: String($0))! })

    /// Finder-like white (daylight.theme).
    public static let daylight = Theme(
        name: "daylight", label: "Daylight", mode: .light,
        background: RGB(hex: "ffffff")!, foreground: RGB(hex: "1d1d1f")!, selection: RGB(hex: "e3edfb")!,
        highlight: RGB(hex: "0a6cd6")!, muted: RGB(hex: "6e6e73")!, accent: RGB(hex: "0a6cd6")!,
        backgroundLighter: RGB(hex: "f5f5f7")!, backgroundDarker: RGB(hex: "e5e5ea")!,
        palette: "1d1d1f d70015 1f7f37 b25000 0040dd 8944ab 0071a4 6e6e73 636366 d1302a 1d8233 946500 0066d6 9a45c8 00789e 1d1d1f"
            .split(separator: " ").map { RGB(hex: String($0))! })
}
