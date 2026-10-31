import Foundation

/// How much the interface animates (UI_MOTION).
public enum ThemeMotion: String, Sendable, CaseIterable {
    case full
    case reduced
}

/// The theme's keys beyond colour (DESIGN.md, "Theme format"): type, corner
/// radii, spacing and motion. Missing or bad values take the defaults, which
/// are the design rules' own numbers.
public struct ThemeTokens: Sendable, Equatable {
    /// FONT_UI and FONT_MONO: family names. "SF Pro" and "SF Mono" mean the system fonts.
    public let fontUI: String
    public let fontMono: String
    /// FONT_SIZE: the row text size in points.
    public let fontSize: Double
    /// RADIUS_WINDOW and RADIUS_CHIP, in points.
    public let radiusWindow: Double
    public let radiusChip: Double
    /// SPACING_UNIT: the step paddings are multiples of, in points.
    public let spacingUnit: Double
    /// UI_MOTION.
    public let motion: ThemeMotion

    public static let standard = ThemeTokens(values: [:])

    public init(values: [String: String]) {
        func text(_ key: String) -> String {
            let value = values[key]?.trimmingCharacters(in: .whitespaces) ?? ""
            return value.isEmpty ? ThemeSpec.fixedDefaults[key] ?? "" : value
        }
        func number(_ key: String) -> Double {
            if let raw = values[key], let n = Int(raw), ThemeSpec.numbers[key]?.contains(n) ?? false { return Double(n) }
            return Double(ThemeSpec.fixedDefaults[key] ?? "0") ?? 0
        }
        fontUI = text("FONT_UI")
        fontMono = text("FONT_MONO")
        fontSize = number("FONT_SIZE")
        radiusWindow = number("RADIUS_WINDOW")
        radiusChip = number("RADIUS_CHIP")
        spacingUnit = number("SPACING_UNIT")
        motion = values["UI_MOTION"].flatMap { ThemeMotion(rawValue: $0.lowercased()) } ?? .full
    }
}
