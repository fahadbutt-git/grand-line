import XCTest
@testable import AppIcon

final class IconThemeTests: XCTestCase {
    /// apps/icons, found from this file's path.
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func values(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let eq = s.firstIndex(of: "=") else { continue }
            out[String(s[..<eq])] = String(s[s.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return out
    }

    func testThemeWithoutIconKeysFallsBack() {
        let theme = IconTheme(values: ["MODE": "dark", "TERM_BG": "202020", "TERM_FG": "dddddd", "ACCENT_HEX": "ff9f0a"])
        XCTAssertEqual(theme.style, .line)
        let p = theme.palette(for: .nexus)
        XCTAssertEqual(p.tile.hex, "202020")
        XCTAssertEqual(p.ink.hex, "dddddd")
        XCTAssertEqual(p.accent.hex, "ff9f0a")
        XCTAssertEqual(p.shade, p.tile)
    }

    func testEmptyThemeStillDraws() {
        let p = IconTheme(values: [:]).palette(for: .iceberg)
        XCTAssertEqual(p.tile.hex, "1c1c1e")
        XCTAssertEqual(p.accent, IconTheme.fallbackAccent)
    }

    func testLightThemeKeepsADarkTileUnlessTold() {
        let light = IconTheme(values: ["MODE": "light", "TERM_BG": "ffffff", "TERM_FG": "1d1d1f", "ACCENT_HEX": "0a6cd6"])
        XCTAssertEqual(light.palette(for: .sight).tile.hex, "1c1c1e")
        let white = IconTheme(values: ["MODE": "light", "ICON_TILE": "ffffff", "ICON_INK": "1d1d1f"])
        XCTAssertEqual(white.palette(for: .sight).tile.hex, "ffffff")
        XCTAssertEqual(white.palette(for: .sight).shade.hex, "1d1d1f")
        XCTAssertGreaterThan(white.palette(for: .iceberg).ice.luminance, 0.2, "the peak is light on a white tile")
    }

    func testPerAppColoursFallBackToTheAccent() {
        let theme = IconTheme(values: ["ICON_ACCENT": "111111", "ICON_SEARCH": "ff0000"])
        XCTAssertEqual(theme.appColor(.sight).hex, "ff0000")
        XCTAssertEqual(theme.appColor(.nexus).hex, "111111")
        XCTAssertEqual(theme.appColor(.iceberg).hex, "111111")
        XCTAssertEqual(IconTheme(values: ["HIGHLIGHT": "222222"]).appColor(.nexus).hex, "222222")
    }

    func testStyles() {
        let base = ["ICON_FILES": "2cc6b4", "ICON_INK": "101010"]
        let solid = IconTheme(values: base.merging(["ICON_STYLE": "solid"]) { $1 }).palette(for: .nexus)
        XCTAssertEqual(solid.tile.hex, "2cc6b4")
        XCTAssertEqual(solid.ink.hex, "101010")
        let mono = IconTheme(values: base.merging(["ICON_STYLE": "MONO"]) { $1 }).palette(for: .nexus)
        XCTAssertEqual(mono.tile.hex, "000000")
        XCTAssertEqual(mono.ink.hex, "2cc6b4")
        XCTAssertEqual(IconTheme(values: ["ICON_STYLE": "sparkly"]).style, .line)
    }

    func testBadHexIsIgnored() {
        let theme = IconTheme(values: ["ICON_TILE": "nope", "ICON_FILES": "12345"])
        XCTAssertEqual(theme.tile, nil)
        XCTAssertEqual(theme.apps[.nexus], nil)
    }

    func testBundledColoursAreGraphite() throws {
        let text = try String(contentsOf: repo.appendingPathComponent("config/themes/graphite.theme"), encoding: .utf8)
        let graphite = IconTheme(values: values(text))
        for glyph in IconGlyph.allCases {
            XCTAssertEqual(graphite.palette(for: glyph), IconTheme.bundled.palette(for: glyph),
                           "graphite.theme changed: update IconTheme.bundled and run tools/make-icons.py")
        }
    }

    func testEveryShippedThemeHasValidIconKeys() throws {
        let folder = repo.appendingPathComponent("config/themes")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".theme") }
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let v = values(try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))
            XCTAssertNotNil(v["ICON_STYLE"].flatMap { IconStyle(rawValue: $0) }, name)
            for key in IconTheme.keys where key != "ICON_STYLE" {
                if let raw = v[key] { XCTAssertNotNil(IconColor(hex: raw), "\(name): \(key)") }
            }
        }
    }

    func testGlyphTablesAreWellFormed() {
        let counts: [IconMark.Kind: Int] = [.rrect: 5, .disc: 3, .ring: 4, .arc: 6, .segment: 5, .ellipse: 4, .lens: 5]
        for glyph in IconGlyph.allCases {
            let marks = IconGlyphs.tile + glyph.marks()
            XCTAssertFalse(glyph.marks().isEmpty)
            for m in marks {
                if m.kind == .polygon {
                    XCTAssertTrue(m.values.count >= 6 && m.values.count % 2 == 0, "\(glyph) \(m)")
                } else {
                    XCTAssertEqual(m.values.count, counts[m.kind], "\(glyph) \(m)")
                }
                XCTAssertTrue(m.values.allSatisfy { $0 >= 0 && $0 <= 1024 || m.kind == .arc }, "\(glyph) \(m)")
            }
        }
        XCTAssertLessThan(IconGlyph.sight.marks(pixels: 32).count, IconGlyph.sight.marks(pixels: 1024).count)
    }
}
