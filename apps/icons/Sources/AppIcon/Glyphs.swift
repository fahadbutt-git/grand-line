import Foundation

/// Which part of the palette a mark is painted with.
public enum IconRole: String, Sendable, CaseIterable {
    case tile, ink, accent, soft, shade
    /// Light against any tile: the iceberg's peak.
    case ice
    /// The accent darkened: veins.
    case deep
    /// The accent a little darker: arteries and the macula.
    case vessel
    /// The accent faded toward warm white: the optic disc and the fovea.
    case pale
}

/// One shape of a glyph, in a 1024 point square with y pointing down.
///
/// | Kind | Values |
/// | --- | --- |
/// | `rrect` | x, y, width, height, corner radius (filled) |
/// | `disc` | centre x, centre y, radius (filled) |
/// | `ring` | centre x, centre y, radius, line width |
/// | `arc` | centre x, centre y, radius, line width, start and end degrees (clockwise from 3 o'clock), round ends |
/// | `segment` | x1, y1, x2, y2, line width, round ends |
/// | `polygon` | x, y pairs (filled) |
/// | `ellipse` | centre x, centre y, x radius, y radius (filled) |
/// | `lens` | centre x, centre y, half width, half height, line width (0 fills it): two circular arcs meeting at the ends |
public struct IconMark: Sendable, Hashable {
    public enum Kind: String, Sendable { case rrect, disc, ring, arc, segment, polygon, ellipse, lens }

    public var kind: Kind
    public var role: IconRole
    public var values: [Double]

    public init(_ kind: Kind, _ role: IconRole, _ values: [Double]) {
        self.kind = kind
        self.role = role
        self.values = values
    }
}

/// The three apps' glyphs. Original, generic shapes.
public enum IconGlyph: String, Sendable, CaseIterable {
    case nexus, sight, iceberg

    /// The theme key for this app's own colour. Named for the app's job,
    /// not its name: files, search, notch.
    public var themeKey: String {
        switch self {
        case .nexus: return "ICON_FILES"
        case .sight: return "ICON_SEARCH"
        case .iceberg: return "ICON_NOTCH"
        }
    }

    /// The marks drawn at `pixels` across: fine detail is left out below
    /// `IconGlyphs.detailSize`, so the icon still reads at 16 and 32.
    public func marks(pixels: Double = IconGlyphs.canvas) -> [IconMark] {
        switch self {
        case .nexus: return IconGlyphs.nexus
        case .sight:
            return pixels >= IconGlyphs.detailSize ? IconGlyphs.sight + IconGlyphs.sightDetail + IconGlyphs.sightTop
                                                   : IconGlyphs.sight + IconGlyphs.sightTop
        case .iceberg: return IconGlyphs.iceberg
        }
    }
}

/// tools/make-icons.py reads these tables to draw the bundled AppIcon.icns
/// files, so both match. Keep one mark per line, in this exact form.
public enum IconGlyphs {
    /// The canvas and Apple's icon grid: an 824 point tile, 100 points in
    /// from each edge, with corners of 185.
    public static let canvas: Double = 1024
    /// Below this many pixels, the detail tables are not drawn.
    public static let detailSize: Double = 64
    public static let tile: [IconMark] = [
        IconMark(.rrect, .tile, [100, 100, 824, 824, 185]),
    ]

    /// Nexus: a sailing ship seen from the side, with a pennant.
    public static let nexus: [IconMark] = [
        IconMark(.segment, .soft, [236, 742, 788, 742, 16]),
        IconMark(.polygon, .accent, [232, 612, 792, 612, 714, 712, 310, 712]),
        IconMark(.segment, .ink, [512, 236, 512, 612, 22]),
        IconMark(.polygon, .ink, [534, 284, 534, 580, 748, 580]),
        IconMark(.polygon, .ink, [490, 336, 490, 580, 312, 580]),
        IconMark(.polygon, .accent, [520, 220, 520, 268, 606, 244]),
    ]

    /// Sight: the back of an eye as an ophthalmoscope shows it. The
    /// optic disc to one side, the superior and inferior arcades (veins, with
    /// thinner, lighter arteries inside them) leaving the disc and curving
    /// around the macula, and the bright fovea at its centre.
    public static let sight: [IconMark] = [
        IconMark(.disc, .accent, [512, 512, 300]),
        IconMark(.disc, .vessel, [420, 520, 64]),
        IconMark(.arc, .deep, [450, 560, 230, 20, 200, 332]),
        IconMark(.arc, .deep, [450, 464, 230, 20, 28, 160]),
        IconMark(.arc, .vessel, [450, 560, 200, 12, 206, 326]),
        IconMark(.arc, .vessel, [450, 464, 200, 12, 34, 154]),
    ]

    /// Sight's smaller branches, drawn from 64 pixels up.
    public static let sightDetail: [IconMark] = [
        IconMark(.segment, .deep, [684, 476, 776, 404, 12]),
        IconMark(.segment, .deep, [684, 548, 776, 620, 12]),
        IconMark(.segment, .vessel, [696, 512, 790, 512, 9]),
        IconMark(.segment, .deep, [450, 330, 432, 244, 10]),
        IconMark(.segment, .deep, [450, 694, 432, 780, 10]),
        IconMark(.segment, .deep, [335, 361, 302, 318, 9]),
        IconMark(.segment, .deep, [335, 663, 302, 706, 9]),
        IconMark(.segment, .vessel, [518, 372, 544, 292, 7]),
        IconMark(.segment, .vessel, [518, 652, 544, 732, 7]),
    ]

    /// Sight's optic disc and fovea, drawn over the vessels.
    public static let sightTop: [IconMark] = [
        IconMark(.ellipse, .pale, [650, 512, 46, 58]),
        IconMark(.disc, .pale, [420, 520, 11]),
    ]

    /// Iceberg: an iceberg, its faceted peak above the waterline and the
    /// larger mass faintly below it.
    public static let iceberg: [IconMark] = [
        IconMark(.polygon, .soft, [282, 596, 770, 596, 834, 690, 724, 800, 432, 812, 236, 700]),
        IconMark(.polygon, .ice, [276, 572, 404, 380, 462, 420, 548, 232, 650, 404, 708, 362, 776, 572]),
        IconMark(.polygon, .accent, [548, 232, 650, 404, 610, 572, 520, 572]),
        IconMark(.polygon, .accent, [708, 362, 776, 572, 704, 572]),
        IconMark(.segment, .accent, [196, 584, 828, 584, 14]),
    ]
}
