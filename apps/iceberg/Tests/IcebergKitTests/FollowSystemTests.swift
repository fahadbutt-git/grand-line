import XCTest
@testable import IcebergKit

/// Following the macOS appearance: the variant Iceberg shows, by the same
/// rules as Nexus and Sight (and `theme mode`).
final class FollowSystemTests: XCTestCase {
    func testShowsTheSystemVariantOnlyWhileFollowing() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        home.write(".grand-line/config/themes/harbour-dark.theme", "FAMILY=harbour\nMODE=dark\n")
        home.write(".grand-line/config/themes/harbour-light.theme", "FAMILY=harbour\nMODE=light\n")
        home.write(".grand-line/config/themes/nord.theme", "MODE=dark\n")
        home.write(".local/state/grand-line/theme", "harbour-dark\n")

        XCTAssertFalse(ThemeLoader.followsSystem(paths: paths))
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, systemIsDark: false), "harbour-dark")

        home.write(".local/state/grand-line/theme-follows-macos", "yes\n")
        XCTAssertTrue(ThemeLoader.followsSystem(paths: paths))
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, systemIsDark: false), "harbour-light")
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, systemIsDark: true), "harbour-dark")
        XCTAssertEqual(ThemeLoader.load(paths: paths, named: "harbour-light").0.mode, .light)

        home.write(".local/state/grand-line/theme", "graphite\n")
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, systemIsDark: false), "daylight", "Graphite pairs with Daylight")

        home.write(".local/state/grand-line/theme", "nord\n")
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, systemIsDark: false), "nord", "Nord has no light variant")
        XCTAssertNil(ThemeLoader.variant(of: "nord", systemIsDark: false, paths: paths))
    }

    /// A reload asks for the appearance at that moment. Nexus running
    /// `theme mode dark` at sunset rewrites the state file; the reload it
    /// causes must show the dark variant even if the appearance notice has
    /// not arrived yet (the old cached value said light).
    func testReloadReadsTheAppearanceFresh() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        home.write(".grand-line/config/themes/harbour-dark.theme", "FAMILY=harbour\nMODE=dark\n")
        home.write(".grand-line/config/themes/harbour-light.theme", "FAMILY=harbour\nMODE=light\n")
        home.write(".local/state/grand-line/theme", "harbour-light\n")

        var dark = false
        var asked = 0
        let appearance = { () -> Bool in asked += 1; return dark }

        XCTAssertEqual(ThemeLoader.followedName(paths: paths, currentAppearanceIsDark: appearance), "harbour-light")
        XCTAssertEqual(asked, 0, "Not following macOS: the appearance is not read")

        home.write(".local/state/grand-line/theme-follows-macos", "yes\n")
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, currentAppearanceIsDark: appearance), "harbour-light")

        dark = true
        home.write(".local/state/grand-line/theme", "harbour-dark\n")
        XCTAssertEqual(ThemeLoader.followedName(paths: paths, currentAppearanceIsDark: appearance), "harbour-dark")
        XCTAssertEqual(asked, 2, "Read on every reload, never cached")
    }
}
