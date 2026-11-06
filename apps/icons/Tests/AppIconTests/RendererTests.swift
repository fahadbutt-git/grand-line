#if canImport(AppKit)
import XCTest
import AppKit
@testable import AppIcon

final class RendererTests: XCTestCase {
    func testEverySizeIsDrawn() {
        for glyph in IconGlyph.allCases {
            let image = IconRenderer.image(glyph)
            XCTAssertEqual(image.representations.count, IconRenderer.sizes.count)
            let big = IconRenderer.cgImage(glyph, palette: .bundled(for: glyph), pixels: 1024)
            XCTAssertEqual(big?.width, 1024)
        }
        XCTAssertTrue(IconRenderer.templateImage(.iceberg).isTemplate)
    }
}
#endif
