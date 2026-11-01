import XCTest
@testable import IcebergKit

/// Hot reload of iceberg.toml: a save that cannot be used keeps the
/// settings in use, never the defaults, and Login Items are only touched
/// when `launch_at_login` itself changes.
final class SettingsReloadTests: XCTestCase {
    let good = """
    launch_at_login = false
    menu_bar_icon = false
    hover_delay = 0.4
    panel = ["date", "today"]
    """

    private func first(_ tmp: TempFolder) -> IcebergSettings {
        let url = tmp.write("iceberg.toml", good)
        let r = IcebergSettings.reload(from: url, previous: nil)
        XCTAssertFalse(r.keptPrevious)
        XCTAssertTrue(r.fileUsable)
        XCTAssertFalse(r.settings.launchAtLogin)
        return r.settings
    }

    func testSyntaxErrorKeepsTheLastGoodSettings() {
        let tmp = TempFolder()
        let before = first(tmp)
        // An editor saves mid-typing.
        let url = tmp.write("iceberg.toml", "launch_at_login = false\npanel = [\"date\",\n")
        let r = IcebergSettings.reload(from: url, previous: before)
        XCTAssertTrue(r.keptPrevious)
        XCTAssertFalse(r.fileUsable)
        XCTAssertEqual(r.settings, before, "not the defaults")
        XCTAssertFalse(r.settings.launchAtLogin)
        XCTAssertFalse(r.settings.menuBarIcon)
        XCTAssertEqual(r.issues.first?.severity, .error)
        XCTAssertTrue(r.issues.first?.message.contains("keeping the last good settings") ?? false)
    }

    func testTruncatedOrMissingFileKeepsTheSettings() {
        let tmp = TempFolder()
        let before = first(tmp)
        let url = tmp.write("iceberg.toml", "")
        XCTAssertEqual(IcebergSettings.reload(from: url, previous: before).settings, before, "nano truncates before it writes")
        XCTAssertTrue(IcebergSettings.reload(from: url, previous: before).keptPrevious)
        try? FileManager.default.removeItem(at: url)
        XCTAssertEqual(IcebergSettings.reload(from: url, previous: before).settings, before, "an editor renames over it")
        let binary = tmp.write("iceberg.toml", data: Data([0xFF, 0xFE, 0x00, 0x80]))
        let r = IcebergSettings.reload(from: binary, previous: before)
        XCTAssertEqual(r.settings, before)
        XCTAssertFalse(r.fileUsable)
    }

    /// A key turned down by the checks keeps its value from before.
    func testRejectedKeyKeepsItsPreviousValue() {
        let tmp = TempFolder()
        let before = first(tmp)
        let url = tmp.write("iceberg.toml", """
        launch_at_login = "no"
        menu_bar_icon = false
        hover_delay = 0.5
        panel = ["date", "today"]
        """)
        let r = IcebergSettings.reload(from: url, previous: before)
        XCTAssertFalse(r.keptPrevious)
        XCTAssertTrue(r.fileUsable)
        XCTAssertFalse(r.settings.launchAtLogin, "the wrong type keeps false, not the default true")
        XCTAssertEqual(r.settings.hoverDelay, 0.5, "the good change still applies")
        XCTAssertFalse(r.issues.isEmpty)
    }

    func testFirstReadOfABrokenFileUsesTheDefaultsButIsNotUsable() {
        let tmp = TempFolder()
        let url = tmp.write("iceberg.toml", "panel = [")
        let r = IcebergSettings.reload(from: url, previous: nil)
        XCTAssertEqual(r.settings, IcebergSettings())
        XCTAssertFalse(r.fileUsable)
        XCTAssertFalse(LoginItemPolicy.shouldApply(wanted: r.settings.launchAtLogin, applied: nil, fileUsable: r.fileUsable),
                       "a broken file never registers the login item")
        XCTAssertTrue(r.issues.first?.message.contains("using the defaults") ?? false)
    }

    func testLoginItemsOnlyFollowAChange() {
        XCTAssertTrue(LoginItemPolicy.shouldApply(wanted: true, applied: nil, fileUsable: true), "first good read")
        XCTAssertFalse(LoginItemPolicy.shouldApply(wanted: true, applied: true, fileUsable: true), "unchanged")
        XCTAssertTrue(LoginItemPolicy.shouldApply(wanted: false, applied: true, fileUsable: true), "turned off")
        XCTAssertFalse(LoginItemPolicy.shouldApply(wanted: true, applied: false, fileUsable: false), "broken file")
    }

    func testLoadIsTheFirstRead() {
        let tmp = TempFolder()
        let url = tmp.write("iceberg.toml", "menu_bar_icon = false\n")
        XCTAssertFalse(IcebergSettings.load(from: url).0.menuBarIcon)
        XCTAssertEqual(IcebergSettings.load(from: tmp.url.appendingPathComponent("none.toml")).0, IcebergSettings())
    }
}
