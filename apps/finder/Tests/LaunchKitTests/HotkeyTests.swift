import XCTest
@testable import LaunchKit

/// The launcher shortcut recorded in Settings, and the Command+Space default.
final class HotkeyTests: XCTestCase {
    func testRecordedShortcutReplacesTheDefault() throws {
        let name = "HotkeyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertNil(HotkeySetting.hotkey(defaults), "nothing until setup hands over Command+Space")
        defaults.set(true, forKey: HotkeySetting.key)
        XCTAssertEqual(HotkeySetting.hotkey(defaults), .commandSpace)

        let optionSpace = LauncherHotkey(keyCode: LauncherHotkey.space, modifiers: LauncherHotkey.option)
        HotkeySetting.setHotkey(optionSpace, defaults)
        XCTAssertEqual(HotkeySetting.hotkey(defaults), optionSpace)
        HotkeySetting.setHotkey(nil, defaults)
        XCTAssertEqual(HotkeySetting.hotkey(defaults), .commandSpace)
    }

    func testDisplayAndUsability() {
        XCTAssertEqual(LauncherHotkey.commandSpace.display, "⌘Space")
        let all = LauncherHotkey(keyCode: 40, modifiers: LauncherHotkey.command | LauncherHotkey.option
            | LauncherHotkey.shift | LauncherHotkey.control)
        XCTAssertEqual(all.display, "⌃⌥⇧⌘K")
        XCTAssertFalse(LauncherHotkey(keyCode: 0, modifiers: LauncherHotkey.shift).isUsable)
        XCTAssertTrue(LauncherHotkey(keyCode: 122, modifiers: 0).isUsable, "a function key alone is fine")
        XCTAssertEqual(LauncherHotkey(defaultsValue: all.defaultsValue), all)
        XCTAssertNil(LauncherHotkey(defaultsValue: ["keyCode": 1]))
    }
}
