import AppKit
import SwiftUI
import XCTest
@testable import ThemeKit

final class ThemeTests: XCTestCase {
    /// config/themes in this repository, found from this file's location.
    static let repoThemes = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ThemeKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // finder
        .deletingLastPathComponent() // apps
        .deletingLastPathComponent() // repository
        .appendingPathComponent("config/themes", isDirectory: true)

    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".local/state/grand-line"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".grand-line/config/themes"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ text: String, _ relative: String) throws {
        try Data(text.utf8).write(to: home.appendingPathComponent(relative))
    }

    // MARK: Every theme in the repository

    func testEveryRepositoryThemeIsReadable() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.repoThemes, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "theme" }
        XCTAssertGreaterThanOrEqual(files.count, 2, Self.repoThemes.path)
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let theme = Theme(name: name, values: try XCTUnwrap(ThemeFile.read(file)))
            for (role, color) in [("text", theme.text), ("dim", theme.dim)] {
                XCTAssertGreaterThanOrEqual(color.contrast(with: theme.background), 4.5, "\(name) \(role) on background")
                XCTAssertGreaterThanOrEqual(color.contrast(with: theme.panel), 4.5, "\(name) \(role) on panel")
            }
            XCTAssertGreaterThanOrEqual(theme.selectionText.contrast(with: theme.selection), 4.5, "\(name) selection")
            XCTAssertEqual(theme.palette.count, 16, name)
        }
    }

    func testBuiltInsMatchTheRepositoryFiles() throws {
        for name in ["graphite", "daylight"] {
            let file = Self.repoThemes.appendingPathComponent(name + ".theme")
            let fromFile = Theme(name: name, values: try XCTUnwrap(ThemeFile.read(file)))
            XCTAssertEqual(BuiltInThemes.named(name), fromFile, name)
        }
        XCTAssertNil(BuiltInThemes.named("nord"))
    }

    // MARK: Derivation

    func testDaylightIsFinderWhite() throws {
        let theme = try XCTUnwrap(BuiltInThemes.named("daylight"))
        XCTAssertFalse(theme.isDark)
        XCTAssertEqual(theme.background.hex, "ffffff")
        XCTAssertEqual(theme.panel.hex, "f5f5f7")
        XCTAssertEqual(theme.line.hex, "e5e5ea")
        XCTAssertEqual(theme.text.hex, "1d1d1f")
        XCTAssertEqual(theme.dim.hex, "6e6e73")
        XCTAssertEqual(theme.selection.hex, "e3edfb")
        XCTAssertEqual(theme.accent.hex, "0a6cd6")
        XCTAssertEqual(theme.label, "Daylight")
    }

    func testGraphiteIsDark() throws {
        let theme = try XCTUnwrap(BuiltInThemes.named("graphite"))
        XCTAssertTrue(theme.isDark)
        XCTAssertEqual(theme.background.hex, "1c1c1e")
        XCTAssertGreaterThan(theme.line.luminance, theme.background.luminance)
        XCTAssertGreaterThan(theme.strong.luminance, theme.text.luminance)
        XCTAssertEqual(theme.highlight.hex, "409cff")
    }

    func testMissingKeysAreDerived() {
        let theme = Theme(name: "mine", values: ["MODE": "dark", "TERM_BG": "202020", "TERM_FG": "dddddd", "MUTED": "333333"])
        XCTAssertEqual(theme.label, "Mine")
        XCTAssertEqual(theme.background.hex, "202020")
        XCTAssertGreaterThanOrEqual(theme.dim.contrast(with: theme.background), 4.5)
        XCTAssertEqual(theme.accent, ThemeColor(hex: "a1a1a6"))
        XCTAssertTrue(theme.palette.isEmpty)
        let guessed = Theme(name: "light", values: ["TERM_BG": "fafafa", "TERM_FG": "202020"])
        XCTAssertFalse(guessed.isDark)
    }

    func testParsing() {
        let values = ThemeFile.parse("# comment\nLABEL=\"My Theme\"\nMODE=light\n\n  ACCENT = 4 \nBROKEN\nPALETTE='a b'\n")
        XCTAssertEqual(values, ["LABEL": "My Theme", "MODE": "light", "ACCENT": "4", "PALETTE": "a b"])
        XCTAssertNil(ThemeFile.read(URL(fileURLWithPath: "/no/such.theme")))
    }

    func testColours() {
        let blue = ThemeColor(hex: "#0A6CD6")
        XCTAssertEqual(blue?.hex, "0a6cd6")
        XCTAssertEqual(blue?.description, "#0a6cd6")
        XCTAssertNil(ThemeColor(hex: "12345"))
        XCTAssertNil(ThemeColor(hex: "zzzzzz"))
        XCTAssertEqual(ThemeColor.black.mixed(with: .white, 0.5).hex, "808080")
        XCTAssertEqual(ThemeColor.white.contrast(with: .black), 21, accuracy: 0.001)
        XCTAssertEqual(ThemeColor.white.contrast(with: .white), 1, accuracy: 0.001)
        XCTAssertEqual(ThemeColor.white.luminance, 1, accuracy: 0.001)
        let grey = ThemeColor(hex: "777777")!
        let lifted = grey.ensuringContrast(7, against: [.black], toward: .white)
        XCTAssertGreaterThanOrEqual(lifted.contrast(with: .black), 7)
        XCTAssertEqual(ThemeColor(red: 2, green: -1, blue: 0.5).red, 1)
    }

    func testAppKitAndSwiftUIColours() {
        let color = ThemeColor(hex: "0a6cd6")!
        let ns = NSColor(color)
        XCTAssertEqual(Double(ns.redComponent), color.red, accuracy: 0.001)
        XCTAssertEqual(Double(ns.blueComponent), color.blue, accuracy: 0.001)
        let resolved = NSColor(Color(color)).usingColorSpace(.sRGB)
        XCTAssertEqual(Double(resolved?.greenComponent ?? 0), color.green, accuracy: 0.01)
        let dark = BuiltInThemes.named("graphite")!
        XCTAssertEqual(dark.colorScheme, .dark)
        XCTAssertEqual(dark.appearanceName, .darkAqua)
        XCTAssertEqual(BuiltInThemes.named("daylight")!.appearanceName, .aqua)
    }

    // MARK: Location and watching

    func testLoadsTheActiveTheme() throws {
        let location = ThemeLocation(home: home)
        XCTAssertNil(location.activeName())
        XCTAssertEqual(location.load().name, "graphite")

        try write("daylight\n", ".local/state/grand-line/theme")
        XCTAssertEqual(location.activeName(), "daylight")
        XCTAssertEqual(location.load().name, "daylight")

        try write("LABEL=\"Paper\"\nMODE=light\nTERM_BG=fbf8f1\nTERM_FG=2b2b2b\n", ".grand-line/config/themes/paper.theme")
        try write("paper", ".local/state/grand-line/theme")
        XCTAssertEqual(location.load().label, "Paper")

        try write("missing", ".local/state/grand-line/theme")
        XCTAssertEqual(location.load().name, "graphite")
        XCTAssertNil(location.load(named: "missing"))
        XCTAssertEqual(location.file(named: "nord").lastPathComponent, "nord.theme")
    }

    func testWatcherPublishesChanges() async throws {
        try write("graphite", ".local/state/grand-line/theme")
        let watcher = ThemeWatcher(location: ThemeLocation(home: home), latency: 0.1)
        XCTAssertEqual(watcher.theme.name, "graphite")
        XCTAssertFalse(watcher.reload())

        try write("daylight", ".local/state/grand-line/theme")
        XCTAssertTrue(watcher.reload())
        XCTAssertEqual(watcher.theme.name, "daylight")
        var iterator = watcher.themes.makeAsyncIterator()
        let published = await iterator.next()
        XCTAssertEqual(published?.name, "daylight")
    }

    func testWatcherFollowsTheDisk() async throws {
        try write("graphite", ".local/state/grand-line/theme")
        let watcher = ThemeWatcher(location: ThemeLocation(home: home), latency: 0.1)
        XCTAssertTrue(watcher.start())
        try await Task.sleep(nanoseconds: 300_000_000)
        try write("daylight", ".local/state/grand-line/theme")
        for _ in 0..<150 where watcher.theme.name != "daylight" {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        watcher.stop()
        XCTAssertEqual(watcher.theme.name, "daylight")
    }
}
