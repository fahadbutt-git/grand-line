import XCTest
@testable import ThemeKit

/// Format 1 (DESIGN.md, "Theme format"): EXTENDS, the checker and its
/// defaults, the tokens beyond colour, and the change notification.
final class ThemeFormatTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeFormatTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    @discardableResult
    private func write(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name + ".theme")
        try Data(text.utf8).write(to: url)
        return url
    }

    private let palette = "PALETTE=\"24262a f2665a 3cc57f e3c24a 6e8bff a281f5 57b4f0 e8e9eb 6d7076 f5857b 63d199 e9ce6e 8ba2ff b59af7 79c3f3 ffffff\"\n"

    /// tests/fixtures/theme-resolved.txt: every shipped theme as `theme resolve` prints it.
    static func shellResolved() throws -> [String: [String: String]] {
        let url = ThemeTests.repoThemes.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tests/fixtures/theme-resolved.txt")
        var themes: [String: [String: String]] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !line.hasPrefix("#") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let pair = line[line.index(after: space)...]
            guard let equals = pair.firstIndex(of: "=") else { continue }
            var value = String(pair[pair.index(after: equals)...])
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            themes[String(line[..<space]), default: [:]][String(pair[..<equals])] = value
        }
        return themes
    }

    func testReadsEveryShippedThemeAsTheShellDoes() throws {
        let expected = try Self.shellResolved()
        XCTAssertGreaterThanOrEqual(expected.count, 16)
        for (name, values) in expected {
            let source = try XCTUnwrap(ThemeSource.resolve(url: ThemeTests.repoThemes.appendingPathComponent(name + ".theme")), name)
            let checked = ThemeSpec.validate(source)
            XCTAssertEqual(checked.values, values, name)
            XCTAssertEqual(checked.errors, [], name)
        }
    }

    func testLightVariantsTakeTheRestFromTheirDarkSibling() throws {
        let source = try XCTUnwrap(ThemeSource.resolve(url: ThemeTests.repoThemes.appendingPathComponent("atlas-light.theme")))
        XCTAssertEqual(source.entries["FAMILY"]?.value, "atlas")
        XCTAssertEqual(source.entries["FAMILY"]?.file, "atlas-dark.theme")
        XCTAssertEqual(source.entries["KIND_STYLE"]?.value, "text")
        XCTAssertEqual(source.entries["MODE"]?.value, "light")
        XCTAssertEqual(source.entries["MODE"]?.file, "atlas-light.theme")
        XCTAssertNil(source.entries["EXTENDS"])
    }

    func testFamilyAndCatalogFollowExtends() throws {
        let home = folder.appendingPathComponent("home")
        let themes = home.appendingPathComponent(".grand-line/config/themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try Data("FORMAT=1\nLABEL=\"Tide Dark\"\nFAMILY=tide\nMODE=dark\nTERM_BG=1b2027\nTERM_FG=dde3ea\n\(palette)".utf8)
            .write(to: themes.appendingPathComponent("tide-dark.theme"))
        try Data("FORMAT=1\nEXTENDS=tide-dark\nLABEL=\"Tide Light\"\nMODE=light\nTERM_BG=ffffff\nTERM_FG=1c1d20\n".utf8)
            .write(to: themes.appendingPathComponent("tide-light.theme"))
        let location = ThemeLocation(home: home)
        XCTAssertEqual(location.family(of: "tide-light"), "tide")
        let light = try XCTUnwrap(location.load(named: "tide-light"))
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.palette.count, 16, "PALETTE comes from tide-dark")
        let family = try XCTUnwrap(ThemeCatalog.families(in: themes).first { $0.id == "tide" })
        XCTAssertTrue(family.hasPair)
        XCTAssertEqual(family.label, "Tide")
    }

    func testAnExtendsLoopIsAnErrorNotAHang() throws {
        try write("a", "FORMAT=1\nEXTENDS=b\n")
        try write("b", "FORMAT=1\nEXTENDS=a\n")
        let source = try XCTUnwrap(ThemeSource.resolve(url: folder.appendingPathComponent("a.theme")))
        XCTAssertTrue(source.diagnostics.contains {
            $0.description == "b.theme:2: error: EXTENDS=a leads back to a (a loop)"
        }, "\(source.diagnostics)")
    }

    func testAMissingParentNamesTheLine() throws {
        let url = try write("c", "FORMAT=1\n# no such parent\nEXTENDS=gone\n")
        let source = try XCTUnwrap(ThemeSource.resolve(url: url))
        XCTAssertEqual(source.diagnostics.map(\.description), ["c.theme:3: error: EXTENDS=gone names no theme (gone.theme is missing)"])
    }

    func testBadValuesAreRejectedWithTheirLine() throws {
        let url = try write("bad", "FORMAT=2\nLABEL=\"Bad\"\nMODE=dusk\nTERM_BG=12345g\nTERM_FG=eeeeee\nPALETTE=\"000000 111111\"\nUI_MOTION=wild\nRADIUS_CHIP=99\n")
        let checked = ThemeSpec.validate(try XCTUnwrap(ThemeSource.resolve(url: url)))
        let lines = Set(checked.errors.map(\.description))
        for expected in [
            "bad.theme:1: error: FORMAT=2 is newer than this version reads (1); update the package",
            "bad.theme:3: error: MODE=dusk must be one of: dark light",
            "bad.theme:4: error: TERM_BG=12345g is not a six-digit hex colour",
            "bad.theme:6: error: PALETTE has 2 colours; it needs 16",
            "bad.theme:7: error: UI_MOTION=wild must be one of: full reduced",
            "bad.theme:8: error: RADIUS_CHIP=99 must be a whole number from 0 to 16",
        ] {
            XCTAssertTrue(lines.contains(expected), "\(expected) not in \(lines)")
        }
        XCTAssertNil(checked.values["TERM_BG"])
    }

    func testDefaultsComeFromTheThemesOwnColours() throws {
        let url = try write("base", "FORMAT=1\nLABEL=\"Base\"\nMODE=dark\nTERM_BG=1a1b1e\nTERM_FG=e8e9eb\n\(palette)KIND_STYLE=dot\n")
        let checked = ThemeSpec.validate(try XCTUnwrap(ThemeSource.resolve(url: url)))
        XCTAssertEqual(checked.diagnostics, [])
        let v = checked.values
        XCTAssertEqual(v["ACCENT_HEX"], "6e8bff")
        XCTAssertEqual(v["HIGHLIGHT"], "6e8bff")
        XCTAssertEqual(v["TERM_SELECTION"], "2f3756")
        XCTAssertEqual(v["MUTED"], "8b8c8f")
        XCTAssertEqual(v["BG_LIGHTER"], "222326")
        XCTAssertEqual(v["BG_DARKER"], "121315")
        XCTAssertEqual(v["KIND_PDF"], "f2665a")
        XCTAssertEqual(v["KIND_TEXT"], "8b8c8f")
        XCTAssertEqual(v["BACKGROUND"], "graphite.jpg")
        XCTAssertEqual(v["UI_MOTION"], "full")
        XCTAssertEqual(v["RADIUS_WINDOW"], "10")
        XCTAssertNil(v["UI_DENSITY"], "density stays each app's own choice")
    }

    func testWeakContrastIsAWarning() throws {
        let url = try write("dim", "FORMAT=1\nLABEL=Dim\nMODE=dark\nTERM_BG=202020\nTERM_FG=444444\nMUTED=303030\n\(palette)")
        let checked = ThemeSpec.validate(try XCTUnwrap(ThemeSource.resolve(url: url)))
        XCTAssertEqual(checked.errors, [])
        XCTAssertTrue(checked.warnings.contains { $0.line == 5 && $0.message.hasPrefix("TERM_FG #444444 is") && $0.message.hasSuffix("text needs 4.5:1") })
        XCTAssertTrue(checked.warnings.contains { $0.line == 6 && $0.message.hasSuffix("secondary text needs 3.0:1") })
    }

    func testLoadedThemesCarryTheirIssues() throws {
        let home = folder.appendingPathComponent("home")
        let themes = home.appendingPathComponent(".grand-line/config/themes")
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
        try Data("LABEL=Old\nMODE=dark\nTERM_BG=202020\nTERM_FG=dddddd\n\(palette)".utf8).write(to: themes.appendingPathComponent("old.theme"))
        let theme = try XCTUnwrap(ThemeLocation(home: home).load(named: "old"))
        XCTAssertEqual(theme.issues.map(\.description), ["old.theme: warning: FORMAT is missing; read as format 1"])
        XCTAssertEqual(ThemeLocation(home: home).check(named: "old")?.errors, [])
    }

    func testTokensBeyondColour() {
        XCTAssertEqual(ThemeTokens.standard.fontUI, "SF Pro")
        XCTAssertEqual(ThemeTokens.standard.fontMono, "SF Mono")
        XCTAssertEqual(ThemeTokens.standard.radiusWindow, 10)
        XCTAssertEqual(ThemeTokens.standard.radiusChip, 5)
        XCTAssertEqual(ThemeTokens.standard.motion, .full)
        let theme = Theme(name: "x", values: ["MODE": "dark", "RADIUS_WINDOW": "12", "UI_MOTION": "Reduced", "SPACING_UNIT": "99"])
        XCTAssertEqual(theme.tokens.radiusWindow, 12)
        XCTAssertEqual(theme.tokens.motion, .reduced)
        XCTAssertEqual(theme.tokens.spacingUnit, 4, "out of range takes the default")
    }

    func testColourKeys() {
        for key in ["TERM_BG", "KIND_PDF", "ICON_TILE", "NOTCH_PANEL", "COLOR3", "COLOR_DANGER"] { XCTAssertTrue(ThemeSpec.isColourKey(key), key) }
        for key in ["KIND_STYLE", "ICON_STYLE", "PALETTE", "LABEL", "UI_MOTION"] { XCTAssertFalse(ThemeSpec.isColourKey(key), key) }
    }

    func testTheChangeNotificationReloadsAtOnce() async throws {
        let home = folder.appendingPathComponent("home")
        let state = home.appendingPathComponent(".local/state/grand-line")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".grand-line/config/themes"), withIntermediateDirectories: true)
        try Data("graphite".utf8).write(to: state.appendingPathComponent("theme"))
        // A long file watch latency, so only the notification can be quick.
        let watcher = ThemeWatcher(location: ThemeLocation(home: home), latency: 30)
        XCTAssertTrue(watcher.start())
        try Data("daylight".utf8).write(to: state.appendingPathComponent("theme"))
        XCTAssertEqual(ThemeWatcher.changedNotification.rawValue, "com.grandline.theme.changed")
        DistributedNotificationCenter.default().postNotificationName(
            ThemeWatcher.changedNotification, object: "daylight", userInfo: nil, deliverImmediately: true)
        for _ in 0..<50 where watcher.theme.name != "daylight" {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        watcher.stop()
        XCTAssertEqual(watcher.theme.name, "daylight")
    }
}
