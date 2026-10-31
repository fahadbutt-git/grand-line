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
}
