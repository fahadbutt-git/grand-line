import XCTest
@testable import IcebergKit

/// Format 1 as Iceberg reads it: the same ThemeSpec.swift as ThemeKit, so
/// the same values as `theme resolve`, with issues that name their line.
final class ThemeFormatTests: XCTestCase {
    private let palette = "PALETTE=\"24262a f2665a 3cc57f e3c24a 6e8bff a281f5 57b4f0 e8e9eb 6d7076 f5857b 63d199 e9ce6e 8ba2ff b59af7 79c3f3 ffffff\"\n"

    func testReadsEveryShippedThemeAsTheShellDoes() throws {
        let text = try String(contentsOf: repoFolder.appendingPathComponent("tests/fixtures/theme-resolved.txt"), encoding: .utf8)
        var expected: [String: [String: String]] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let pair = line[line.index(after: space)...]
            guard let equals = pair.firstIndex(of: "=") else { continue }
            var value = String(pair[pair.index(after: equals)...])
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            expected[String(line[..<space]), default: [:]][String(pair[..<equals])] = value
        }
        XCTAssertGreaterThanOrEqual(expected.count, 16)
        let folder = repoFolder.appendingPathComponent("config/themes")
        for (name, values) in expected {
            let source = try XCTUnwrap(ThemeSource.resolve(url: folder.appendingPathComponent(name + ".theme")), name)
            XCTAssertEqual(ThemeSpec.validate(source).values, values, name)
        }
    }

    func testALightVariantInheritsItsFamily() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        home.write(".grand-line/config/themes/tide-dark.theme",
                   "FORMAT=1\nLABEL=\"Tide Dark\"\nFAMILY=tide\nMODE=dark\nTERM_BG=1b2027\nTERM_FG=dde3ea\nNOTCH_CARD=2a3038\n\(palette)")
        home.write(".grand-line/config/themes/tide-light.theme",
                   "FORMAT=1\nEXTENDS=tide-dark\nLABEL=\"Tide Light\"\nMODE=light\nTERM_BG=ffffff\nTERM_FG=1c1d20\n")
        XCTAssertEqual(ThemeLoader.resolvedFields(paths: paths, named: "tide-light")["FAMILY"], "tide")
        XCTAssertEqual(ThemeLoader.resolvedFields(paths: paths, named: "tide-light")["NOTCH_CARD"], "2a3038")
        XCTAssertEqual(ThemeLoader.variant(of: "tide-light", systemIsDark: true, paths: paths), "tide-dark")
        let (theme, issues) = ThemeLoader.load(paths: paths, named: "tide-light")
        XCTAssertEqual(issues, [])
        XCTAssertEqual(theme.mode, .light)
        XCTAssertEqual(theme.palette.count, 16)
        XCTAssertEqual(theme.background.hex, "ffffff")
    }

    func testIssuesNameTheirLine() {
        let (theme, issues) = ThemeLoader.parse("FORMAT=1\nLABEL=X\nMODE=dark\nTERM_BG=zz\nTERM_FG=eeeeee\n\(palette)", name: "x")
        XCTAssertEqual(theme.background, Theme.graphite.background, "a bad required colour shows the base theme's")
        XCTAssertTrue(issues.contains(ConfigIssue(file: "x.theme", line: 4, message: "TERM_BG=zz is not a six-digit hex colour", severity: .error)),
                      "\(issues)")
    }

    func testAMissingParentIsAnIssue() {
        let home = TempFolder()
        let paths = IcebergPaths(home: home.url)
        home.write(".grand-line/config/themes/lost.theme", "FORMAT=1\nEXTENDS=gone\nLABEL=Lost\nMODE=dark\nTERM_BG=202020\nTERM_FG=dddddd\n\(palette)")
        let (theme, issues) = ThemeLoader.load(paths: paths, named: "lost")
        XCTAssertEqual(theme.label, "Lost")
        XCTAssertTrue(issues.contains { $0.line == 2 && $0.message.contains("EXTENDS=gone names no theme") }, "\(issues)")
    }

    func testTheChangeNotificationName() {
        XCTAssertEqual(ThemeLoader.changedNotification.rawValue, "com.grandline.theme.changed")
    }
}
