import XCTest
import AppIcon
@testable import ThemeKit

final class KindsAndIconTests: XCTestCase {
    func testEveryRepositoryThemeHasKindsAndIcons() throws {
        let files = try FileManager.default.contentsOfDirectory(at: ThemeTests.repoThemes, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "theme" }
        for file in files {
            let values = try XCTUnwrap(ThemeFile.read(file))
            let name = file.deletingPathExtension().lastPathComponent
            XCTAssertNotNil(values["KIND_STYLE"].flatMap(KindStyle.init(rawValue:)), "\(name): KIND_STYLE")
            XCTAssertNotNil(values["ICON_STYLE"].flatMap(IconStyle.init(rawValue:)), "\(name): ICON_STYLE")
            for kind in FileKindName.allCases {
                XCTAssertNotNil(values[kind.themeKey].flatMap(ThemeColor.init(hex:)), "\(name): \(kind.themeKey)")
            }
            let theme = Theme(name: name, values: values)
            XCTAssertEqual(theme.kinds.colors.count, FileKindName.allCases.count, name)
            if let family = values["FAMILY"] {
                XCTAssertTrue(name == family + "-dark" || name == family + "-light", name)
                XCTAssertEqual(theme.isDark, name.hasSuffix("-dark"), name)
            }
        }
    }

    func testKindsFallBackToThePalette() {
        let palette = "000000 ff0000 00ff00 ffff00 0000ff ff00ff 00ffff ffffff 111111 220000 002200 222200 000022 220022 002222 eeeeee"
        let theme = Theme(name: "plain", values: ["MODE": "dark", "TERM_BG": "101010", "TERM_FG": "eeeeee",
                                                  "ACCENT_HEX": "123456", "PALETTE": palette, "KIND_PDF": "abcdef"])
        XCTAssertEqual(theme.kinds.style, .tag)
        XCTAssertEqual(theme.kinds[.pdf].hex, "abcdef")
        XCTAssertEqual(theme.kinds[.folder].hex, "123456")
        XCTAssertEqual(theme.kinds[.document].hex, "0000ff")
        XCTAssertEqual(theme.kinds[.text], theme.dim)
        XCTAssertEqual(Theme(name: "x", values: ["KIND_STYLE": "DOT"]).kinds.style, .dot)
        XCTAssertEqual(Theme(name: "x", values: ["KIND_STYLE": "fancy"]).kinds.style, .tag)
    }

    func testOptionalSurfaceKeys() {
        let theme = Theme(name: "x", values: ["MODE": "dark", "TERM_BG": "1a1b1e", "TERM_FG": "e8e9eb",
                                              "SIDEBAR": "151619", "FIELD": "24262a", "LINE": "2a2c30", "BG_LIGHTER": "24262a"])
        XCTAssertEqual(theme.panel.hex, "151619")
        XCTAssertEqual(theme.field.hex, "24262a")
        XCTAssertEqual(theme.line.hex, "2a2c30")
    }

    func testIconFallsBackToItsOwnTheme() {
        let theme = Theme(name: "mine", values: ["MODE": "dark", "TERM_BG": "202020", "TERM_FG": "dddddd", "ACCENT_HEX": "ff9f0a"])
        let palette = theme.icon.palette(for: .nexus)
        XCTAssertEqual(palette.tile.hex, "202020")
        XCTAssertEqual(palette.ink.hex, "dddddd")
        XCTAssertEqual(palette.accent.hex, "ff9f0a")
        // A change to an icon key alone is a different theme, so the watcher republishes it.
        let changed = Theme(name: "mine", values: ["MODE": "dark", "TERM_BG": "202020", "TERM_FG": "dddddd",
                                                   "ACCENT_HEX": "ff9f0a", "ICON_STYLE": "mono"])
        XCTAssertNotEqual(theme, changed)
    }

    func testGraphiteMatchesTheBundledIcons() throws {
        let graphite = try XCTUnwrap(BuiltInThemes.named("graphite"))
        for glyph in IconGlyph.allCases {
            XCTAssertEqual(graphite.icon.palette(for: glyph), IconTheme(values: [
                "MODE": "dark", "TERM_BG": "1c1c1e", "TERM_FG": "e5e5e7",
                "ICON_STYLE": "line", "ICON_FILES": "409cff", "ICON_SEARCH": "ff6a3d", "ICON_NOTCH": "64d2ff",
            ]).palette(for: glyph))
        }
    }
}
