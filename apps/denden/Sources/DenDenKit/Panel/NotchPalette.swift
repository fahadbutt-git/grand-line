import Foundation

/// The open panel's own colours. Every one comes from the theme file:
/// `NOTCH_PANEL`, `NOTCH_CARD` and `NOTCH_LINE` when a theme sets them,
/// else the theme's surface, raised surface and line colours.
public struct NotchPalette: Equatable, Sendable {
    /// The open panel below the camera band.
    public var panel: RGB
    /// Chips and other raised things in the panel.
    public var card: RGB
    /// The dividers between columns.
    public var line: RGB

    public static let keys = ["NOTCH_PANEL", "NOTCH_CARD", "NOTCH_LINE"]

    /// `fields` are the theme file's KEY=value pairs; `theme` is it parsed.
    public init(fields: [String: String], theme: Theme) {
        func color(_ key: String) -> RGB? { fields[key].flatMap(RGB.init(hex:)) }
        panel = color("NOTCH_PANEL") ?? theme.background
        card = color("NOTCH_CARD") ?? color("FIELD") ?? theme.backgroundLighter
        line = color("NOTCH_LINE") ?? color("LINE") ?? panel.mixed(with: theme.foreground, theme.mode == .dark ? 0.16 : 0.12)
    }

    public init(panel: RGB, card: RGB, line: RGB) {
        self.panel = panel
        self.card = card
        self.line = line
    }
}

/// What a script widget's chip says. A command that prints a bare setup
/// token ("Set LOCATION", "Bad API_KEY") gets a plain note instead, with
/// the token kept for the tooltip.
public enum ChipText {
    public static let needsSetup = "Needs setup"

    public static func shown(_ text: String) -> (text: String, needsSetup: Bool) {
        let words = text.split(separator: " ")
        guard words.count == 2, ["Set", "Bad", "Missing", "No", "Need"].contains(String(words[0])) else { return (text, false) }
        let token = words[1]
        let isToken = token.count >= 2 && token.allSatisfy { ($0.isUppercase && $0.isASCII) || $0.isNumber || $0 == "_" }
            && token.contains(where: \.isLetter)
        return isToken ? (needsSetup, true) : (text, false)
    }
}
