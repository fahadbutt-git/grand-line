import XCTest
@testable import ThemeKit

/// The Appearance pane's models: theme families listed from a folder of
/// theme files, the variant chosen while following macOS, and the `theme`
/// arguments each choice runs.
final class AppearanceSettingsTests: XCTestCase {
    private var home: URL!
    private var themes: URL { home.appendingPathComponent(".grand-line/config/themes") }
    private var location: ThemeLocation { ThemeLocation(home: home) }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("AppearanceSettingsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/state/grand-line"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func theme(_ name: String, mode: String, family: String? = nil, label: String? = nil, bg: String) throws {
        var text = "LABEL=\"\(label ?? name.capitalized)\"\nMODE=\(mode)\nTERM_BG=\(bg)\nTERM_FG=\(mode == "dark" ? "e5e5e7" : "1d1d1f")\n"
        if let family { text += "FAMILY=\(family)\n" }
        try Data(text.utf8).write(to: themes.appendingPathComponent(name + ".theme"))
    }

    private func setActive(_ name: String) throws {
        try Data((name + "\n").utf8).write(to: location.stateFile)
    }

    private func sampleFolder() throws {
        try theme("harbour-dark", mode: "dark", family: "harbour", label: "Harbour Dark", bg: "1a1b1e")
        try theme("harbour-light", mode: "light", family: "harbour", label: "Harbour Light", bg: "f7f8fa")
        try theme("graphite", mode: "dark", bg: "1c1c1e")
        try theme("daylight", mode: "light", bg: "ffffff")
        try theme("nord", mode: "dark", label: "Nord", bg: "2e3440")
        try theme("zebra", mode: "light", label: "Zebra", bg: "fafafa")
    }

    // MARK: Families from a folder

    func testFamiliesGroupPairsAndKeepSingles() throws {
        try sampleFolder()
        let families = ThemeCatalog.families(in: themes)
        XCTAssertEqual(families.map(\.id), ["harbour", "system", "nord", "zebra"])

        let harbour = try XCTUnwrap(families.first { $0.id == "harbour" })
        XCTAssertEqual(harbour.label, "Harbour")
        XCTAssertEqual(harbour.dark?.name, "harbour-dark")
        XCTAssertEqual(harbour.light?.name, "harbour-light")
        XCTAssertTrue(harbour.hasPair)
        XCTAssertTrue(harbour.isFilePair)

        let system = try XCTUnwrap(families.first { $0.id == "system" })
        XCTAssertEqual(system.label, "Graphite and Daylight")
        XCTAssertEqual(system.dark?.name, "graphite")
        XCTAssertEqual(system.light?.name, "daylight")
        XCTAssertFalse(system.isFilePair)

        let nord = try XCTUnwrap(families.first { $0.id == "nord" })
        XCTAssertEqual(nord.label, "Nord")
        XCTAssertFalse(nord.hasPair)
        XCTAssertEqual(nord.variant(dark: false)?.name, "nord", "a single theme is its own light variant too")
        XCTAssertEqual(ThemeCatalog.family(of: "harbour-light", in: families)?.id, "harbour")
    }

    func testEmptyFolderFallsBackToTheBuiltInPair() {
        let families = ThemeCatalog.families(in: home.appendingPathComponent("missing"))
        XCTAssertEqual(families.map(\.id), ["system"])
        XCTAssertEqual(families.first?.variants.count, 2)
    }

    func testRepositoryThemesListEveryFamilyInOrder() throws {
        let families = ThemeCatalog.families(in: ThemeTests.repoThemes)
        XCTAssertEqual(families.map(\.id), ThemeCatalog.preferredOrder)
        for family in families where family.id != "nord" && family.id != "forest" {
            XCTAssertTrue(family.hasPair, "\(family.id) should have a dark and a light variant")
            XCTAssertTrue(family.dark?.isDark ?? false)
            XCTAssertFalse(family.light?.isDark ?? true)
        }
    }

    // MARK: Following macOS

    func testFollowVariantChoice() {
        let all: Set<String> = ["harbour-dark", "harbour-light", "graphite", "daylight", "nord"]
        let exists: (String) -> Bool = { all.contains($0) }
        XCTAssertEqual(ThemeFollow.variant(of: "harbour-dark", systemIsDark: false, family: "harbour", exists: exists), "harbour-light")
        XCTAssertNil(ThemeFollow.variant(of: "harbour-dark", systemIsDark: true, family: "harbour", exists: exists), "already matches")
        XCTAssertEqual(ThemeFollow.variant(of: "graphite", systemIsDark: false, family: ThemeFollow.systemFamily, exists: exists), "daylight")
        XCTAssertEqual(ThemeFollow.variant(of: "daylight", systemIsDark: true, family: ThemeFollow.systemFamily, exists: exists), "graphite")
        XCTAssertNil(ThemeFollow.variant(of: "nord", systemIsDark: false, family: nil, exists: exists), "no light Nord")
        XCTAssertNil(ThemeFollow.variant(of: "lantern-dark", systemIsDark: false, family: "lantern", exists: exists), "missing file")
        XCTAssertEqual(ThemeFollow.modeArguments(systemIsDark: true), ["mode", "dark"])
    }

    func testLocationShowsTheSystemVariantOnlyWhileFollowing() throws {
        try sampleFolder()
        try setActive("harbour-dark")
        XCTAssertEqual(location.resolvedName(systemIsDark: false), "harbour-dark", "not following yet")
        XCTAssertEqual(location.load(systemIsDark: false).name, "harbour-dark")

        try location.setFollowsSystem(true)
        XCTAssertTrue(location.followsSystem())
        XCTAssertEqual(location.resolvedName(systemIsDark: false), "harbour-light")
        XCTAssertEqual(location.load(systemIsDark: false).name, "harbour-light")
        XCTAssertEqual(location.resolvedName(systemIsDark: true), "harbour-dark")

        try setActive("graphite")
        XCTAssertEqual(location.resolvedName(systemIsDark: false), "daylight")
        try setActive("nord")
        XCTAssertEqual(location.resolvedName(systemIsDark: false), "nord")

        try location.setFollowsSystem(false)
        XCTAssertFalse(location.followsSystem())
        try setActive("harbour-dark")
        XCTAssertEqual(location.resolvedName(systemIsDark: false), "harbour-dark")
    }

    func testWatcherSwitchesVariantWhenTheSystemChanges() throws {
        try sampleFolder()
        try setActive("harbour-dark")
        try location.setFollowsSystem(true)
        let watcher = ThemeWatcher(location: location)
        watcher.systemAppearanceChanged(isDark: true)
        XCTAssertEqual(watcher.theme.name, "harbour-dark")
        watcher.systemAppearanceChanged(isDark: false)
        XCTAssertEqual(watcher.theme.name, "harbour-light")
        watcher.systemAppearanceChanged(isDark: true)
        XCTAssertEqual(watcher.theme.name, "harbour-dark")
    }

    func testFollowLockIsTakenOnce() throws {
        let lock = location.followLock
        XCTAssertTrue(ThemeFollow.takeLock(lock))
        XCTAssertFalse(ThemeFollow.takeLock(lock), "a second app finds it taken")
        XCTAssertTrue(ThemeFollow.takeLock(lock, now: Date().addingTimeInterval(120)), "a stale lock is taken over")
    }

    // MARK: The theme command's arguments

    func testSetArgumentsForEachAppearance() throws {
        try sampleFolder()
        let families = ThemeCatalog.families(in: themes)
        let harbour = try XCTUnwrap(families.first { $0.id == "harbour" })
        let system = try XCTUnwrap(families.first { $0.id == "system" })
        let nord = try XCTUnwrap(families.first { $0.id == "nord" })

        XCTAssertEqual(ThemeCommand.setArguments(harbour, appearance: .system, systemIsDark: false), ["set", "harbour"])
        XCTAssertEqual(ThemeCommand.setArguments(harbour, appearance: .dark, systemIsDark: false), ["set", "harbour-dark"])
        XCTAssertEqual(ThemeCommand.setArguments(harbour, appearance: .light, systemIsDark: true), ["set", "harbour-light"])
        XCTAssertEqual(ThemeCommand.setArguments(system, appearance: .system, systemIsDark: false), ["set", "daylight"])
        XCTAssertEqual(ThemeCommand.setArguments(system, appearance: .dark, systemIsDark: false), ["set", "graphite"])
        XCTAssertEqual(ThemeCommand.setArguments(nord, appearance: .light, systemIsDark: false), ["set", "nord"])
        XCTAssertEqual(ThemeCommand.Outcome(status: 0, output: "one\ntwo\n").lastLine, "two")
    }

    // MARK: Density

    func testDensityComesFromTheThemeThenTheDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AppearanceSettingsTests-\(UUID().uuidString)"))
        XCTAssertEqual(Density.current(theme: nil, defaults: defaults), .regular)
        defaults.set("compact", forKey: Density.defaultsKey)
        XCTAssertEqual(Density.current(theme: nil, defaults: defaults), .compact)
        let roomy = Theme(name: "roomy", values: ["MODE": "dark", "UI_DENSITY": "comfortable"])
        XCTAssertEqual(Density.current(theme: roomy, defaults: defaults), .comfortable)
        XCTAssertEqual(Density.compact.scaled(24), 20)
        XCTAssertEqual(Density.comfortable.scaled(24), 29)
    }
}
