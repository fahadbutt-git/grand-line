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

    func testTheShortcutToRegisterIsKnownBeforeItIsSaved() throws {
        let name = "HotkeyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let optionSpace = LauncherHotkey(keyCode: LauncherHotkey.space, modifiers: LauncherHotkey.option)
        XCTAssertEqual(HotkeySetting.resolved(optionSpace, defaults), optionSpace)
        XCTAssertNil(HotkeySetting.resolved(nil, defaults))
        defaults.set(true, forKey: HotkeySetting.key)
        XCTAssertEqual(HotkeySetting.resolved(nil, defaults), .commandSpace)
        XCTAssertNil(defaults.object(forKey: HotkeySetting.hotkeyKey), "resolving saves nothing")
    }

    /// A handle that says when it is let go, as HotKey unregisters on deinit.
    final class Handle {
        let name: String
        let released: (String) -> Void
        init(_ name: String, released: @escaping (String) -> Void) {
            self.name = name
            self.released = released
        }
        deinit { released(name) }
    }

    func testARefusedShortcutKeepsTheOldOne() {
        var released: [String] = []
        var registration = HotkeyRegistration<Handle>()
        let commandSpace = LauncherHotkey.commandSpace
        let taken = LauncherHotkey(keyCode: 40, modifiers: LauncherHotkey.command)
        let free = LauncherHotkey(keyCode: LauncherHotkey.space, modifiers: LauncherHotkey.option)
        var order: [String] = []
        func register(_ key: LauncherHotkey) -> Handle? {
            order.append("register \(key.display)")
            guard key != taken else { return nil }
            return Handle(key.display) { released.append($0); order.append("release \($0)") }
        }
        XCTAssertTrue(registration.change(to: commandSpace, register: register))
        XCTAssertFalse(registration.change(to: taken, register: register))
        XCTAssertEqual(registration.shortcut, commandSpace, "the old shortcut still works")
        XCTAssertNotNil(registration.handle)
        XCTAssertTrue(released.isEmpty)
        XCTAssertTrue(registration.change(to: free, register: register))
        XCTAssertEqual(registration.shortcut, free)
        XCTAssertEqual(order, ["register ⌘Space", "register ⌘K", "register ⌥Space", "release ⌘Space"],
                       "the new one is held before the old one goes")
        XCTAssertTrue(registration.change(to: free, register: register))
        XCTAssertEqual(order.count, 4, "the same shortcut is not registered twice")
        registration.suspend()
        XCTAssertNil(registration.handle)
        XCTAssertEqual(released, ["⌘Space", "⌥Space"])
        XCTAssertTrue(registration.change(to: nil, register: register))
        XCTAssertNil(registration.shortcut)
    }
}
