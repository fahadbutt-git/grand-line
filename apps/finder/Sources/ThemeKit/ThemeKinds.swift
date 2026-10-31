import Foundation

/// The kinds of file Nexus and Sight colour, and the KIND_* theme key of each.
public enum FileKindName: String, Sendable, CaseIterable {
    case folder, document, pdf, presentation, spreadsheet, image, video, code, archive, text

    public var themeKey: String { "KIND_" + rawValue.uppercased() }
}

/// How a file's kind is shown beside its name (`KIND_STYLE`).
public enum KindStyle: String, Sendable, CaseIterable {
    /// A small tinted tag with the extension.
    case tag
    /// A coloured dot.
    case dot
    /// A filled tag in the kind's colour.
    case solid
    /// The kind's name in its colour, no shape.
    case text
}

/// The colour of each kind of file, from the KIND_* keys. A theme without
/// them takes the terminal colours, so every theme has all ten.
public struct ThemeKinds: Sendable, Equatable {
    public let style: KindStyle
    public let colors: [FileKindName: ThemeColor]

    public subscript(kind: FileKindName) -> ThemeColor { colors[kind] ?? .black }

    init(values: [String: String], palette: [ThemeColor], accent: ThemeColor, dim: ThemeColor) {
        style = values["KIND_STYLE"].flatMap { KindStyle(rawValue: $0.lowercased()) } ?? .tag
        func paletteColor(_ i: Int) -> ThemeColor { i < palette.count ? palette[i] : accent }
        let fallback: [FileKindName: ThemeColor] = [
            .folder: accent, .document: paletteColor(4), .pdf: paletteColor(1), .presentation: paletteColor(3),
            .spreadsheet: paletteColor(2), .image: paletteColor(5), .video: paletteColor(13), .code: paletteColor(11),
            .archive: paletteColor(9), .text: dim,
        ]
        var colors: [FileKindName: ThemeColor] = [:]
        for kind in FileKindName.allCases {
            colors[kind] = values[kind.themeKey].flatMap(ThemeColor.init(hex:)) ?? fallback[kind]
        }
        self.colors = colors
    }
}
