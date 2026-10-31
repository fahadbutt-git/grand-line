import Foundation

/// How the icons are coloured (`ICON_STYLE` in the theme file).
public enum IconStyle: String, Sendable, CaseIterable {
    /// A dark tile with a light glyph and the app's colour as its hot point.
    case line
    /// The app's colour as the tile, with a dark glyph.
    case solid
    /// A black tile with the whole glyph in the app's colour.
    case mono
}

/// The five colours one icon is drawn with.
public struct IconPalette: Sendable, Hashable {
    /// The rounded square behind the glyph.
    public var tile: IconColor
    /// The glyph's main lines and shapes.
    public var ink: IconColor
    /// The hot point: the hull and pennant, the back of the eye, the ice facet.
    public var accent: IconColor
    /// Quiet fills: the sea, the iceberg under water.
    public var soft: IconColor
    /// The darker of tile and ink.
    public var shade: IconColor
    /// Always light against the tile: the iceberg's peak.
    public var ice: IconColor

    public init(tile: IconColor, ink: IconColor, accent: IconColor, soft: IconColor, shade: IconColor, ice: IconColor) {
        self.tile = tile
        self.ink = ink
        self.accent = accent
        self.soft = soft
        self.shade = shade
        self.ice = ice
    }

    static let warmWhite = IconColor(hex: "fff6dc")!

    public func color(_ role: IconRole) -> IconColor {
        switch role {
        case .tile: return tile
        case .ink: return ink
        case .accent: return accent
        case .soft: return soft
        case .shade: return shade
        case .ice: return ice
        case .deep: return accent.mixed(with: .black, 0.42)
        case .vessel: return accent.mixed(with: .black, 0.24)
        case .pale: return accent.mixed(with: Self.warmWhite, 0.8)
        }
    }
}

/// The icon keys of a theme file, with what each falls back to, so a theme
/// written before the keys existed still gives every app an icon.
///
/// | Key | Meaning | Missing |
/// | --- | --- | --- |
/// | `ICON_STYLE` | line, solid or mono | line |
/// | `ICON_TILE` | the tile (line and mono) | line: TERM_BG of a dark theme, else 1c1c1e; mono: 000000 |
/// | `ICON_INK` | the glyph (line and solid) | line: TERM_FG of a dark theme, else e5e5e7; solid: 1c1c1e |
/// | `ICON_ACCENT` | every app's colour | ACCENT_HEX, then HIGHLIGHT |
/// | `ICON_SOFT` | quiet fills | the tile with 24% of the accent |
/// | `ICON_FILES`, `ICON_SEARCH`, `ICON_NOTCH` | one app's colour (Log Pose, Byakugan, Den Den) | ICON_ACCENT |
public struct IconTheme: Sendable, Hashable {
    public static let keys = ["ICON_STYLE", "ICON_TILE", "ICON_INK", "ICON_ACCENT", "ICON_SOFT"]
        + IconGlyph.allCases.map(\.themeKey)

    public static let fallbackAccent = IconColor(hex: "409cff")!

    /// The colours of the bundled AppIcon.icns (tools/make-icons.py draws
    /// them for Graphite). The tests check they still match graphite.theme.
    public static let bundled = IconTheme(values: [
        "MODE": "dark", "TERM_BG": "1c1c1e", "TERM_FG": "e5e5e7", "ACCENT_HEX": "98989d", "HIGHLIGHT": "409cff",
        "ICON_STYLE": "line", "ICON_FILES": "409cff", "ICON_SEARCH": "ff6a3d", "ICON_NOTCH": "64d2ff",
    ])
    static let darkTile = IconColor(hex: "1c1c1e")!
    static let lightInk = IconColor(hex: "e5e5e7")!
    static let solidAccent = IconColor(hex: "f5f5f7")!

    public var style: IconStyle
    public var isDark: Bool
    public var tile: IconColor?
    public var ink: IconColor?
    public var accent: IconColor?
    public var soft: IconColor?
    public var background: IconColor?
    public var foreground: IconColor?
    public var apps: [IconGlyph: IconColor]

    /// From a theme file's KEY=value pairs (any keys; the unknown are ignored).
    public init(values: [String: String]) {
        func color(_ key: String) -> IconColor? { values[key].flatMap(IconColor.init(hex:)) }
        style = values["ICON_STYLE"].flatMap { IconStyle(rawValue: $0.lowercased()) } ?? .line
        background = color("TERM_BG")
        foreground = color("TERM_FG")
        if let mode = values["MODE"]?.lowercased(), mode == "dark" || mode == "light" {
            isDark = mode == "dark"
        } else {
            isDark = (background?.luminance ?? 0) < 0.4
        }
        tile = color("ICON_TILE")
        ink = color("ICON_INK")
        accent = color("ICON_ACCENT") ?? color("ACCENT_HEX") ?? color("HIGHLIGHT")
        soft = color("ICON_SOFT")
        var apps: [IconGlyph: IconColor] = [:]
        for glyph in IconGlyph.allCases {
            if let c = color(glyph.themeKey) { apps[glyph] = c }
        }
        self.apps = apps
    }

    /// The app's own colour: its ICON_<APP> key, else the icon accent.
    public func appColor(_ glyph: IconGlyph) -> IconColor {
        apps[glyph] ?? accent ?? Self.fallbackAccent
    }

    public func palette(for glyph: IconGlyph) -> IconPalette {
        let app = appColor(glyph)
        let tile: IconColor
        let ink: IconColor
        let accent: IconColor
        switch style {
        case .line:
            tile = self.tile ?? (isDark ? (background ?? Self.darkTile) : Self.darkTile)
            ink = self.ink ?? (isDark ? (foreground ?? Self.lightInk) : Self.lightInk)
            accent = app
        case .solid:
            tile = app
            ink = self.ink ?? Self.darkTile
            accent = Self.solidAccent
        case .mono:
            tile = self.tile ?? .black
            ink = app
            accent = app.mixed(with: .white, 0.45)
        }
        let soft = self.soft ?? tile.mixed(with: accent, 0.24)
        let shade = ink.luminance < tile.luminance ? ink : tile
        let ice: IconColor
        switch style {
        case .line: ice = tile.luminance < 0.4 ? ink : accent.mixed(with: .white, 0.55)
        case .solid: ice = tile.mixed(with: .white, 0.7)
        case .mono: ice = ink
        }
        return IconPalette(tile: tile, ink: ink, accent: accent, soft: soft, shade: shade, ice: ice)
    }
}
