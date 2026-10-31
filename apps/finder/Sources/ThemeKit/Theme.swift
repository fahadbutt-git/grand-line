import Foundation
import AppIcon

/// The colours an app window uses, derived from a theme file. Text and dim text
/// always reach 4.5:1 against the background and the panel.
public struct Theme: Sendable, Equatable {
    public let name: String
    public let label: String
    public let isDark: Bool

    /// The window and list background (TERM_BG).
    public let background: ThemeColor
    /// The sidebar and toolbar (BG_LIGHTER).
    public let panel: ThemeColor
    /// Text fields and the search box.
    public let field: ThemeColor
    /// Dividers between panes.
    public let line: ThemeColor
    /// Row separators, quieter than `line`.
    public let hairline: ThemeColor
    /// Body text (TERM_FG).
    public let text: ThemeColor
    /// Titles and the selected item's name.
    public let strong: ThemeColor
    /// Secondary text: sizes, dates, paths (MUTED).
    public let dim: ThemeColor
    /// Placeholders and disabled items.
    public let faint: ThemeColor
    /// The selected row (TERM_SELECTION).
    public let selection: ThemeColor
    public let selectionText: ThemeColor
    /// Controls and links (ACCENT_HEX).
    public let accent: ThemeColor
    /// Matched letters and the focused item (HIGHLIGHT).
    public let highlight: ThemeColor
    /// Background of query chips and tags.
    public let chip: ThemeColor
    /// The 16 terminal colours.
    public let palette: [ThemeColor]
    /// The colour of each kind of file and how kinds are shown (KIND_*).
    public let kinds: ThemeKinds
    /// The app icons' colours (ICON_*).
    public let icon: IconTheme

    /// Missing keys come from the built-in theme of the same mode.
    public init(name: String, values: [String: String]) {
        let mode = values["MODE"]?.lowercased()
        let base = mode == "light" ? BuiltInThemes.daylight : BuiltInThemes.graphite
        func color(_ key: String) -> ThemeColor? {
            values[key].flatMap(ThemeColor.init(hex:))
        }
        func required(_ key: String) -> ThemeColor {
            color(key) ?? base[key].flatMap(ThemeColor.init(hex:)) ?? .black
        }

        let background = required("TERM_BG")
        let isDark = mode.map { $0 == "dark" } ?? (background.luminance < 0.4)
        let toward: ThemeColor = isDark ? .white : .black
        let rawText = required("TERM_FG")
        let palette = (values["PALETTE"] ?? "").split(separator: " ").compactMap { ThemeColor(hex: String($0)) }

        // SIDEBAR, FIELD and LINE are optional; most themes derive them.
        let panel = color("SIDEBAR") ?? color("BG_LIGHTER") ?? background.mixed(with: rawText, 0.04)
        let text = rawText.ensuringContrast(4.5, against: [background, panel], toward: toward)
        let accent = color("ACCENT_HEX") ?? color("HIGHLIGHT") ?? (palette.count > 4 ? palette[4] : nil) ?? required("TERM_CURSOR")
        let selection = color("TERM_SELECTION") ?? background.mixed(with: accent, 0.25)

        self.name = name
        self.label = values["LABEL"] ?? name.capitalized
        self.isDark = isDark
        self.background = background
        self.panel = panel
        self.field = color("FIELD")
            ?? (isDark ? (color("BG_DARKER") ?? background.mixed(with: .black, 0.3)) : background.mixed(with: text, 0.05))
        // A darker line disappears on a dark background, so dark themes derive theirs.
        self.line = color("LINE")
            ?? (isDark ? background.mixed(with: text, 0.16) : (color("BG_DARKER") ?? background.mixed(with: text, 0.1)))
        self.hairline = background.mixed(with: text, isDark ? 0.10 : 0.07)
        self.text = text
        self.strong = text.mixed(with: toward, 0.5)
        let dim = (color("MUTED") ?? text.mixed(with: background, 0.45))
            .ensuringContrast(4.5, against: [background, panel], toward: text)
        self.dim = dim
        self.faint = text.mixed(with: background, 0.6)
        self.selection = selection
        self.selectionText = text.ensuringContrast(4.5, against: [selection], toward: toward)
        self.accent = accent
        self.highlight = color("HIGHLIGHT") ?? accent
        self.chip = background.mixed(with: accent, isDark ? 0.22 : 0.12)
        self.palette = palette
        self.kinds = ThemeKinds(values: values, palette: palette, accent: accent, dim: dim)
        // The icon falls back to this theme's own background and text, never another theme's.
        self.icon = IconTheme(values: values.merging(
            ["MODE": isDark ? "dark" : "light", "TERM_BG": background.hex, "TERM_FG": rawText.hex,
             "ACCENT_HEX": accent.hex]) { mine, _ in mine })
    }
}
