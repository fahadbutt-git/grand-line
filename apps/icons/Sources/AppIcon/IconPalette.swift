import Foundation

/// The five colours one icon is drawn with.
public struct IconPalette: Sendable, Hashable {
    /// The rounded square behind the glyph.
    public var tile: IconColor
    /// The glyph's main lines and shapes.
    public var ink: IconColor
    /// The hot point: the back of the eye, the ice facet.
    public var accent: IconColor
    /// Quiet fills: the iceberg under water.
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

public extension IconPalette {
    /// The colours of the bundled AppIcon.icns, which tools/make-icons.py
    /// draws with the same values: a dark tile, a light glyph and the app's
    /// own colour as its hot point.
    static func bundled(for glyph: IconGlyph) -> IconPalette {
        let tile = IconColor(hex: "1c1c1e")!
        let ink = IconColor(hex: "e5e5e7")!
        let accent = glyph.color
        return IconPalette(tile: tile, ink: ink, accent: accent, soft: tile.mixed(with: accent, 0.24),
                           shade: ink.luminance < tile.luminance ? ink : tile, ice: ink)
    }
}
