import XCTest
@testable import DenDenKit

final class PanelLayoutTests: XCTestCase {
    func testFirstRunShowsTheDefaultsAndNoExamples() {
        let layout = PanelLayout(settings: DenDenSettings())
        XCTAssertEqual(layout.enabled, ["date", "now-playing", "today"])
        XCTAssertEqual(layout.widgets(available: ["weather", "services"]), [])
    }

    func testOlderFilesKeepTheirBuiltinList() {
        let (s, issues) = DenDenSettings.parse("builtin = [\"reminders\", \"battery\"]")
        XCTAssertEqual(issues, [])
        XCTAssertEqual(PanelLayout(settings: s).enabled, ["date", "reminders", "battery"])
    }

    func testPanelKeyWins() {
        let (s, issues) = DenDenSettings.parse("""
        builtin = ["battery"]
        panel = ["weather", "today", "weather", "gone"]
        menu_bar_icon = false
        """)
        XCTAssertEqual(issues, [])
        XCTAssertFalse(s.menuBarIcon)
        let layout = PanelLayout(settings: s)
        XCTAssertEqual(layout.enabled, ["weather", "today", "gone"])
        XCTAssertEqual(layout.builtins, ["today"])
        // A widget that is not there is kept but not shown.
        XCTAssertEqual(layout.widgets(available: ["weather", "services"]), ["weather"])
        let (empty, _) = DenDenSettings.parse("panel = []")
        XCTAssertEqual(PanelLayout(settings: empty).enabled, [])
    }

    func testPanelWithBadEntriesWarns() {
        let (s, issues) = DenDenSettings.parse("panel = [\"today\", 3]")
        XCTAssertEqual(s.panel, ["today"])
        XCTAssertEqual(issues.count, 1)
    }

    func testTogglingAndOrder() {
        var layout = PanelLayout(enabled: ["date", "now-playing", "today"])
        layout.set("weather", enabled: true)
        XCTAssertEqual(layout.enabled, ["date", "now-playing", "today", "weather"])
        layout.set("weather", enabled: true)
        XCTAssertEqual(layout.enabled.count, 4)
        layout.set("now-playing", enabled: false)
        XCTAssertEqual(layout.enabled, ["date", "today", "weather"])
        layout.move(["weather"], before: "date")
        XCTAssertEqual(layout.enabled, ["weather", "date", "today"])
        layout.move(["weather"], before: nil)
        XCTAssertEqual(layout.enabled, ["date", "today", "weather"])
        layout.move(["date"], before: "date")
        XCTAssertEqual(layout.enabled, ["date", "today", "weather"])
        layout.move(["nope"], before: "date")
        XCTAssertEqual(layout.enabled, ["date", "today", "weather"])
    }

    func testUpAndDownSkipHiddenNames() {
        var layout = PanelLayout(enabled: ["date", "gone", "today", "weather"])
        let visible = ["date", "today", "weather"]
        layout.move("today", by: -1, among: visible)
        XCTAssertEqual(layout.enabled, ["today", "date", "gone", "weather"])
        layout.move("today", by: -1, among: visible)
        XCTAssertEqual(layout.enabled, ["today", "date", "gone", "weather"])
        layout.move("date", by: 1, among: visible)
        XCTAssertEqual(layout.enabled.filter(visible.contains), ["today", "weather", "date"])
        layout.move("date", by: 1, among: visible)
        XCTAssertEqual(layout.enabled.filter(visible.contains), ["today", "weather", "date"])
    }

    func testCatalogue() {
        XCTAssertEqual(PanelCatalog.builtins.map(\.id), ["date", "now-playing", "today", "reminders", "battery"])
        XCTAssertEqual(PanelCatalog.builtin("today")?.permission, .calendars)
        XCTAssertEqual(PanelCatalog.builtin("reminders")?.permission, .reminders)
        XCTAssertNil(PanelCatalog.builtin("now-playing")?.permission)
        // Every built-in widget the old `builtin` key named is in the catalogue.
        for name in DenDenSettings.builtinWidgets { XCTAssertTrue(PanelCatalog.isBuiltin(name), name) }
        for item in PanelCatalog.builtins { XCTAssertFalse(item.detail.isEmpty, item.id) }
    }
}

final class TOMLEditorTests: XCTestCase {
    func testLiterals() {
        XCTAssertEqual(TOMLEditor.literal(.array([.string("a\"b"), .string("c\\d")])), #"["a\"b", "c\\d"]"#)
        XCTAssertEqual(TOMLEditor.literal(.bool(false)), "false")
        XCTAssertEqual(TOMLEditor.literal(.float(0.25)), "0.25")
        XCTAssertEqual(TOMLEditor.literal(.string("tab\there\u{01}")), #""tab\there\u0001""#)
        XCTAssertEqual(try TOML.parse("k = " + TOMLEditor.literal(.string("tab\there\u{01}\n")))["k"], .string("tab\there\u{01}\n"))
    }

    func testReplacingKeepsCommentsAndOtherLines() throws {
        let text = """
        # My notch settings
        open_on = "hover"   # I like hover

        # Which things show
        builtin = [
          "today",   # first
          "battery",
        ]
        live_activity = true
        """
        let edited = try TOMLEditor.setting("open_on", to: .string("click"), in: text)
        XCTAssertEqual(edited, text.replacingOccurrences(of: "open_on = \"hover\"", with: "open_on = \"click\""))
        let list = try TOMLEditor.setting("builtin", to: .array([.string("reminders")]), in: edited)
        XCTAssertTrue(list.contains("# Which things show\nbuiltin = [\"reminders\"]\nlive_activity = true"), list)
        XCTAssertTrue(list.contains("# I like hover"))
        XCTAssertEqual(try TOML.parse(list)["builtin"], .array([.string("reminders")]))
    }

    func testAddingGoesAfterTheLastTopLevelKeyAndBeforeTables() throws {
        let text = "hover_delay = 0.2\n\n[extra]\nname = \"x\"\n"
        let edited = try TOMLEditor.setting("panel", to: .array([.string("date")]), in: text)
        XCTAssertEqual(edited, "hover_delay = 0.2\npanel = [\"date\"]\n\n[extra]\nname = \"x\"\n")
        XCTAssertEqual(try TOML.parse(edited)["extra.name"], .string("x"))

        let noNewline = try TOMLEditor.setting("open_on", to: .string("click"), in: "# only a comment")
        XCTAssertEqual(noNewline, "# only a comment\nopen_on = \"click\"\n")
        XCTAssertEqual(try TOMLEditor.setting("a", to: .bool(true), in: ""), "a = true\n")
        let tableFirst = try TOMLEditor.setting("a", to: .bool(true), in: "[t]\nb = 1\n")
        XCTAssertEqual(tableFirst, "a = true\n\n[t]\nb = 1\n")
    }

    func testKeysInsideTablesAreNotTouched() throws {
        let text = "[weather]\nopen_on = \"x\"\n"
        let edited = try TOMLEditor.setting("open_on", to: .string("click"), in: text)
        let table = try TOML.parse(edited)
        XCTAssertEqual(table["open_on"], .string("click"))
        XCTAssertEqual(table["weather.open_on"], .string("x"))
    }

    func testRemoving() throws {
        let text = "a = 1\nbuiltin = [\n  \"today\",\n]  # old\nb = 2\n"
        XCTAssertEqual(try TOMLEditor.removing("builtin", in: text), "a = 1\nb = 2\n")
        XCTAssertEqual(try TOMLEditor.removing("missing", in: text), text)
    }

    func testBrokenFilesAreNotWritten() {
        XCTAssertThrowsError(try TOMLEditor.setting("a", to: .bool(true), in: "open_on = \"click"))
    }

    func testValuesWithHashesAndQuotes() throws {
        let text = "title = \"a # not a \\\"comment\\\"\" # real\nnext = 'it is'\n"
        let edited = try TOMLEditor.setting("title", to: .string("b"), in: text)
        XCTAssertEqual(edited, "title = \"b\" # real\nnext = 'it is'\n")
    }

    func testSettingsRoundTripThroughTheFile() throws {
        let folder = TempFolder()
        let url = folder.url.appendingPathComponent("denden/denden.toml")
        try DenDenSettings.write("open_on", .string("click"), to: url)
        try DenDenSettings.write("hover_delay", .float(0.3), to: url)
        try DenDenSettings.write("launch_at_login", .bool(false), to: url)
        var layout = PanelLayout(settings: DenDenSettings.load(from: url).0)
        layout.set("weather", enabled: true)
        layout.move(["weather"], before: "today")
        try DenDenSettings.write("panel", layout.value, to: url)
        let (s, issues) = DenDenSettings.load(from: url)
        XCTAssertEqual(issues, [])
        XCTAssertEqual(s.openOn, .click)
        XCTAssertEqual(s.hoverDelay, 0.3)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(PanelLayout(settings: s).enabled, ["date", "now-playing", "weather", "today"])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Den Den's settings."), text)
    }

    func testWritingPanelRetiresBuiltin() throws {
        let folder = TempFolder()
        let url = folder.write("denden.toml", "# mine\nbuiltin = [\"battery\"]\nopen_on = \"click\"\n")
        let layout = PanelLayout(settings: DenDenSettings.load(from: url).0)
        XCTAssertEqual(layout.enabled, ["date", "battery"])
        try DenDenSettings.write("panel", layout.value, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, "# mine\nopen_on = \"click\"\npanel = [\"date\", \"battery\"]\n")
    }
}

final class TintAndTextTests: XCTestCase {
    func testDominantColourOfACover() {
        // Mostly red, some grey.
        var pixels: [UInt8] = []
        for i in 0..<100 { pixels += i < 70 ? [200, 30, 30, 255] : [120, 120, 120, 255] }
        let tint = ArtworkTint.dominant(rgba: pixels)
        XCTAssertEqual(tint?.hex, "c81e1e")
    }

    func testGreyCoversFallBackToTheAccent() {
        let grey = [UInt8](repeating: 128, count: 400).enumerated().map { $0.offset % 4 == 3 ? 255 : $0.element }
        XCTAssertNil(ArtworkTint.dominant(rgba: grey))
        XCTAssertNil(ArtworkTint.dominant(rgba: []))
        let accent = RGB(hex: "0a6cd6")!
        let tint = ArtworkTint.tint(cover: nil, accent: accent)
        XCTAssertGreaterThanOrEqual(RGB.contrast(tint, RGB(hex: "000000")!), 4.5)
    }

    func testDarkCoversAreLiftedToRead() {
        let navy = RGB(hex: "101a50")!
        let lifted = ArtworkTint.readableOnBlack(navy)
        XCTAssertGreaterThanOrEqual(RGB.contrast(lifted, RGB(hex: "000000")!), 4.5)
        let bright = RGB(hex: "ffd60a")!
        XCTAssertEqual(ArtworkTint.readableOnBlack(bright), bright)
    }

    func testSetupTokensAreNotShown() {
        XCTAssertEqual(ChipText.shown("Set LOCATION").text, ChipText.needsSetup)
        XCTAssertTrue(ChipText.shown("Bad API_KEY").needsSetup)
        XCTAssertEqual(ChipText.shown("Set alarm").text, "Set alarm")
        XCTAssertEqual(ChipText.shown("12°C Sunny").text, "12°C Sunny")
        XCTAssertEqual(ChipText.shown("No 3").text, "No 3")
    }

    func testNotchPaletteKeysAndFallbacks() {
        let theme = Theme.graphite
        let plain = NotchPalette(fields: [:], theme: theme)
        XCTAssertEqual(plain.panel, theme.background)
        XCTAssertEqual(plain.card, theme.backgroundLighter)
        let set = NotchPalette(fields: ["NOTCH_PANEL": "101010", "FIELD": "202020", "LINE": "303030"], theme: theme)
        XCTAssertEqual(set.panel.hex, "101010")
        XCTAssertEqual(set.card.hex, "202020")
        XCTAssertEqual(set.line.hex, "303030")
        XCTAssertEqual(NotchPalette(fields: ["NOTCH_CARD": "aaaaaa", "FIELD": "202020"], theme: theme).card.hex, "aaaaaa")
    }
}
