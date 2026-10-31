import XCTest
@testable import IcebergKit

final class ThemeTests: XCTestCase {
    func testHexColours() {
        XCTAssertEqual(RGB(hex: "#1c1c1e")?.hex, "1c1c1e")
        XCTAssertEqual(RGB(hex: "fff")?.hex, "ffffff")
        XCTAssertNil(RGB(hex: "12345"))
        XCTAssertNil(RGB(hex: "gggggg"))
    }

    func testFieldsParser() {
        let f = ThemeLoader.fields("""
        # comment
        LABEL="Sample Theme"
        export MODE=light
        TERM_BG = ffffff
        MUTED=6e6e73 # trailing
        BAD LINE
        """)
        XCTAssertEqual(f["LABEL"], "Sample Theme")
        XCTAssertEqual(f["MODE"], "light")
        XCTAssertEqual(f["TERM_BG"], "ffffff")
        XCTAssertEqual(f["MUTED"], "6e6e73")
        XCTAssertNil(f["BAD LINE"])
    }

    func testEveryShippedThemeParsesCleanly() throws {
        let folder = repoFolder.appendingPathComponent("config/themes")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".theme") }
        XCTAssertFalse(names.isEmpty, "no themes in \(folder.path)")
        for name in names {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            // A light variant takes some keys from the dark one it EXTENDS.
            let fields = ThemeSpec.validate(ThemeSource.resolve(text: text, file: name, folder: folder)).values
            for key in Theme.requiredKeys { XCTAssertNotNil(fields[key], "\(name) lacks \(key)") }
            let (theme, issues) = ThemeLoader.parse(text, name: String(name.dropLast(6)), folder: folder)
            XCTAssertEqual(issues.filter { $0.severity == .error }, [], name)
            XCTAssertEqual(theme.palette.count, 16, name)
            // DESIGN.md: text keeps 4.5:1 against the background.
            XCTAssertGreaterThanOrEqual(RGB.contrast(theme.foreground, theme.background), 4.5, name)
        }
    }

    func testBuiltInFallbacksMatchTheShippedFiles() throws {
        for fallback in [Theme.graphite, Theme.daylight] {
            let url = repoFolder.appendingPathComponent("config/themes/\(fallback.name).theme")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let (parsed, _) = ThemeLoader.parse(text, name: fallback.name)
            XCTAssertEqual(parsed, fallback, "\(fallback.name) changed; update Theme.\(fallback.name)")
        }
    }

    func testModesPickTheRightBase() {
        let (light, _) = ThemeLoader.parse("MODE=light\nLABEL=X", name: "x")
        XCTAssertEqual(light.mode, .light)
        XCTAssertEqual(light.background, Theme.daylight.background)
        let (bad, issues) = ThemeLoader.parse("MODE=purple", name: "y")
        XCTAssertEqual(bad.mode, .dark)
        XCTAssertTrue(issues.contains { $0.message.contains("MODE") })
    }

    func testBadValuesAreReportedNotFatal() {
        let (theme, issues) = ThemeLoader.parse("MODE=dark\nTERM_BG=nothex\nPALETTE=\"aa\"", name: "z")
        XCTAssertEqual(theme.background, Theme.graphite.background)
        XCTAssertTrue(issues.contains { $0.message.contains("TERM_BG") })
        XCTAssertTrue(issues.contains { $0.message.contains("PALETTE") })
    }

    func testLoadingFromAHomeFolder() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        // No state file: graphite.
        XCTAssertEqual(ThemeLoader.currentName(paths: paths), "graphite")
        XCTAssertEqual(ThemeLoader.load(paths: paths).0.name, "graphite")

        home.write(".local/state/grand-line/theme", "daylight\n")
        home.write(".grand-line/config/themes/daylight.theme", "LABEL=\"Daylight\"\nMODE=light\nTERM_BG=fafafa\n")
        let (theme, _) = ThemeLoader.load(paths: paths)
        XCTAssertEqual(theme.mode, .light)
        XCTAssertEqual(theme.background.hex, "fafafa")

        // A theme name that is not a plain file name is refused.
        home.write(".local/state/grand-line/theme", "../../etc/passwd\n")
        XCTAssertEqual(ThemeLoader.currentName(paths: paths), "graphite")
    }

    func testThemeColourNames() {
        let t = Theme.graphite
        XCTAssertEqual(t.color(.red), t.palette[1])
        XCTAssertEqual(t.color(.cyan), t.palette[6])
        XCTAssertEqual(t.resolve(.theme(.highlight)), t.highlight)
        XCTAssertEqual(t.resolve(.hex(RGB(red: 0, green: 0, blue: 0))).hex, "000000")
    }

    func testMissingFilesWarnOnlyForThemesIcebergDoesNotCarry() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        // No state file and no theme files, as in a build run before setup.
        let (fresh, quiet) = ThemeLoader.load(paths: paths)
        XCTAssertEqual(fresh.name, "graphite")
        XCTAssertEqual(quiet, [])

        home.write(".local/state/grand-line/theme", "daylight\n")
        let (daylight, none) = ThemeLoader.load(paths: paths)
        XCTAssertEqual(daylight.mode, .light)
        XCTAssertEqual(none, [])

        home.write(".local/state/grand-line/theme", "ocean\n")
        let (fallback, issues) = ThemeLoader.load(paths: paths)
        XCTAssertEqual(fallback.name, "graphite")
        XCTAssertEqual(issues.map(\.file), ["ocean.theme"])
        XCTAssertTrue(issues.first?.message.contains("not found") ?? false)
    }
}
