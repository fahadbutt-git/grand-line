import XCTest
@testable import IcebergKit

final class MotionAndSurfaceTests: XCTestCase {
    func testWhatMerelyAppearsNeverOvershoots() {
        for spring in [MotionSpec.open, MotionSpec.close, MotionSpec.wings, MotionSpec.basket,
                       MotionSpec.content, MotionSpec.release] {
            XCTAssertEqual(spring.dampingFraction, 1, "\(spring) overshoots")
            XCTAssertFalse(spring.bounces)
        }
    }

    func testOnlyMomentumBounces() {
        XCTAssertTrue(MotionSpec.drop.bounces)
        XCTAssertGreaterThanOrEqual(MotionSpec.drop.dampingFraction, 0.7)
    }

    func testClosingIsNoSlowerThanOpening() {
        XCTAssertLessThanOrEqual(MotionSpec.close.response, MotionSpec.open.response)
    }

    func testTimingsStayShort() {
        XCTAssertLessThanOrEqual(MotionSpec.pressDuration, 0.1)
        XCTAssertLessThanOrEqual(MotionSpec.fadeDuration, 0.2)
        let slowest = [MotionSpec.open, MotionSpec.close, MotionSpec.wings, MotionSpec.basket, MotionSpec.drop].map(\.response).max() ?? 0
        XCTAssertGreaterThan(MotionSpec.settleFallback, slowest * 2)
        XCTAssertLessThan(MotionSpec.pressedScale, 1)
        XCTAssertLessThan(MotionSpec.materialiseScale, 1)
    }

    func testSurfaceIsTranslucentByDefault() {
        let s = SurfaceStyle.resolve(reduceTransparency: false, increaseContrast: false)
        XCTAssertTrue(s.usesMaterial)
        XCTAssertLessThan(s.tintOpacity, 1)
        XCTAssertEqual(s.edgePixels, 1)
    }

    func testReduceTransparencyMakesItSolid() {
        let s = SurfaceStyle.resolve(reduceTransparency: true, increaseContrast: false)
        XCTAssertFalse(s.usesMaterial)
        XCTAssertEqual(s.tintOpacity, 1)
    }

    func testIncreaseContrastIsSolidWithADefinedEdge() {
        for reduce in [false, true] {
            let s = SurfaceStyle.resolve(reduceTransparency: reduce, increaseContrast: true)
            XCTAssertFalse(s.usesMaterial)
            XCTAssertEqual(s.tintOpacity, 1)
            XCTAssertGreaterThan(s.edgeEmphasis, 0)
            XCTAssertGreaterThan(s.edgePixels, 1)
        }
        XCTAssertGreaterThan(SurfaceStyle.lineEmphasis(increaseContrast: true), 0)
        XCTAssertEqual(SurfaceStyle.lineEmphasis(increaseContrast: false), 0)
    }

    func testHairlinesAreOneDevicePixel() {
        XCTAssertEqual(PixelGrid.hairline(scale: 2), 0.5)
        XCTAssertEqual(PixelGrid.hairline(scale: 1), 1)
        XCTAssertEqual(PixelGrid.hairline(scale: 0), 1)
        XCTAssertEqual(PixelGrid.width(pixels: 2, scale: 2), 1)
    }

    func testAlignSnapsToThePixelGrid() {
        XCTAssertEqual(PixelGrid.align(10.3, scale: 2), 10.5)
        XCTAssertEqual(PixelGrid.align(10.2, scale: 2), 10)
        XCTAssertEqual(PixelGrid.align(10.4, scale: 1), 10)
        XCTAssertEqual(PixelGrid.floor(1.78, scale: 2), 1.5)
        XCTAssertEqual(PixelGrid.floor(1.78, scale: 3), 5.0 / 3)
    }
}
