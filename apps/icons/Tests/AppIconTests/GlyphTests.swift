import XCTest
@testable import AppIcon

final class GlyphTests: XCTestCase {
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

    func testBundledPalette() {
        let p = IconPalette.bundled(for: .sight)
        XCTAssertEqual(p.tile.hex, "1c1c1e")
        XCTAssertEqual(p.ink.hex, "e5e5e7")
        XCTAssertEqual(p.accent.hex, "ff6a3d")
        XCTAssertEqual(p.shade, p.tile)
        XCTAssertEqual(IconPalette.bundled(for: .iceberg).accent.hex, "64d2ff")
    }
}
