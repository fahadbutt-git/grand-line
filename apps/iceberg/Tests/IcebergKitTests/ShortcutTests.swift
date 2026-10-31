import XCTest
@testable import IcebergKit

final class ShortcutTests: XCTestCase {
    func testDefaultMatchesTheCapsLockBinding() throws {
        let d = KeyShortcut.defaultToggle
        XCTAssertEqual(d.text, "ctrl+option+cmd+n")
        XCTAssertEqual(d.symbols, "⌃⌥⌘N")
        XCTAssertEqual(d.keyCode, 45)
        XCTAssertEqual(KeyShortcut.parse("ctrl+option+cmd+n"), d)
        // The package's own binding opens the panel with Caps Lock + Control + Option + N.
        let bindings = try String(contentsOf: repoFolder.appendingPathComponent("tools/bindings.py"), encoding: .utf8)
        XCTAssertTrue(bindings.contains(#"("n", ["control", "option"], "Apps", "Open or close the notch panel (Iceberg)""#))
    }

    func testSpellings() {
        let expected = KeyShortcut(key: "n", keyCode: 45, modifiers: [.control, .option, .command])
        for text in ["Control+Alt+Command+N", "ctl+opt+cmd+n", "⌃⌥⌘N", "⌃⌥⌘+n", " cmd + ctrl + option + n "] {
            XCTAssertEqual(KeyShortcut.parse(text), expected, text)
        }
        XCTAssertEqual(KeyShortcut.parse("cmd+shift+space")?.text, "shift+cmd+space")
        XCTAssertEqual(KeyShortcut.parse("ctrl+f5")?.keyCode, 96)
        XCTAssertEqual(KeyShortcut.parse("option+esc")?.key, "escape")
        XCTAssertEqual(KeyShortcut.parse("cmd+up")?.symbols, "⌘↑")
    }

    func testRefused() {
        for text in ["", "n", "shift+n", "hyper+n", "ctrl+", "ctrl+nope", "ctrl++", "cmd+f20"] {
            XCTAssertNil(KeyShortcut.parse(text), text)
        }
        XCTAssertNil(KeyShortcut(keyCode: 45, modifiers: [.shift]))
        XCTAssertNil(KeyShortcut(keyCode: 999, modifiers: [.command]))
    }

    func testCarbonModifiers() {
        XCTAssertEqual(KeyShortcut.defaultToggle.carbonModifiers, (1 << 8) | (1 << 11) | (1 << 12))
        XCTAssertEqual(KeyShortcut.parse("shift+cmd+k")?.carbonModifiers, (1 << 8) | (1 << 9))
    }

    func testEveryKeyCodeRoundTrips() {
        for (name, code) in KeyShortcut.keyCodes {
            XCTAssertEqual(KeyShortcut.name(forKeyCode: code), name)
            let s = KeyShortcut(keyCode: code, modifiers: [.control])
            XCTAssertEqual(s.flatMap { KeyShortcut.parse($0.text) }, s, name)
        }
    }
}
