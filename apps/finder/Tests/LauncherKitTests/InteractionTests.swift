import XCTest
@testable import LauncherKit

final class InteractionTests: XCTestCase {
    func key(_ code: UInt16, _ chars: String = "", command: Bool = false, shift: Bool = false, control: Bool = false) -> KeyCommand? {
        KeyCommand.command(for: KeyPress(keyCode: code, characters: chars, command: command, shift: shift, control: control))
    }

    func testKeys() {
        XCTAssertEqual(key(KeyPress.Code.returnKey), .primary)
        XCTAssertEqual(key(KeyPress.Code.returnKey, command: true), .secondary)
        XCTAssertEqual(key(40, "k", command: true), .actions)
        XCTAssertEqual(key(18, "1", command: true), .runRow(1))
        XCTAssertEqual(key(25, "9", command: true), .runRow(9))
        XCTAssertEqual(key(KeyPress.Code.escape), .escape)
        XCTAssertEqual(key(KeyPress.Code.up), .moveUp)
        XCTAssertEqual(key(KeyPress.Code.down), .moveDown)
        XCTAssertEqual(key(45, "n", control: true), .moveDown)
        XCTAssertEqual(key(KeyPress.Code.tab), .complete)
        XCTAssertEqual(key(16, "y", command: true), .togglePreview)
        XCTAssertEqual(key(8, "c", command: true), .copy)
        XCTAssertEqual(key(8, "c", command: true, shift: true), .shortcut(KeyShortcut("c", shift: true)))
    }

    func testTypingAndEditingKeysStayInTheField() {
        XCTAssertNil(key(0, "a"))
        XCTAssertNil(key(0, "a", command: true))
        XCTAssertNil(key(9, "v", command: true))
        XCTAssertNil(key(KeyPress.Code.space, " "))
    }

    func testEscapeClearsThenCloses() {
        XCTAssertEqual(EscapeRule.outcome(actionPanelOpen: true, confirming: true, query: "x"), .closeActionPanel)
        XCTAssertEqual(EscapeRule.outcome(actionPanelOpen: false, confirming: true, query: "x"), .cancelConfirmation)
        XCTAssertEqual(EscapeRule.outcome(actionPanelOpen: false, confirming: false, query: "x"), .clearQuery)
        XCTAssertEqual(EscapeRule.outcome(actionPanelOpen: false, confirming: false, query: ""), .closeWindow)
    }

    func testConfirmationNeedsASecondReturn() {
        var gate = ConfirmationGate()
        let quit = LaunchAction("Quit", symbol: "x", confirmation: "Quit Safari?", .quit(pid: 42, force: false))
        XCTAssertFalse(gate.shouldRun(quit, on: "proc:42"))
        XCTAssertTrue(gate.isConfirming)
        XCTAssertTrue(gate.shouldRun(quit, on: "proc:42"))
        XCTAssertFalse(gate.isConfirming)
        // A different row starts over.
        XCTAssertFalse(gate.shouldRun(quit, on: "proc:1"))
        XCTAssertFalse(gate.shouldRun(quit, on: "proc:42"))
        gate.cancel()
        XCTAssertFalse(gate.isConfirming)
        XCTAssertTrue(gate.shouldRun(LaunchAction("Open", symbol: "app", .open("/x")), on: "a"))
    }

    func testFooterShowsTheRowsShortcuts() {
        var row = Make.row("Notes")
        row.actions += [LaunchAction("Reveal", symbol: "folder", .reveal("/x")), LaunchAction("Copy", symbol: "doc", .copyText("x"))]
        row.previewPath = "/x"
        let hints = FooterHints.hints(for: row, confirming: nil)
        // "Open ↵ · Reveal ⌘↵ · Actions ⌘K": Quick Look is in the action panel.
        XCTAssertEqual(hints.map(\.keys), ["↵", "⌘↵", "⌘K"])
        XCTAssertEqual(hints.map(\.label), ["Open", "Reveal", "Actions"])
        var gate = ConfirmationGate()
        _ = gate.shouldRun(LaunchAction("Quit", symbol: "x", confirmation: "Quit Safari?", .quit(pid: 1, force: false)), on: "p")
        XCTAssertEqual(FooterHints.hints(for: row, confirming: gate.pending).first?.label, "Quit Safari?")
    }

    func testKeyCombinationParsing() {
        let maccy = KeyShortcut("c", shift: true)
        XCTAssertEqual(KeyShortcut(parsing: "⇧⌘C"), maccy)
        XCTAssertEqual(KeyShortcut(parsing: "Shift+Command+C"), maccy)
        XCTAssertEqual(KeyShortcut(parsing: "cmd + shift + c"), maccy)
        XCTAssertEqual(KeyShortcut(parsing: "⌃⌥Space"), KeyShortcut("space", command: false, option: true, control: true))
        XCTAssertEqual(KeyShortcut(parsing: "k"), KeyShortcut("k", command: false))
        XCTAssertNil(KeyShortcut(parsing: "⌘"))
        XCTAssertNil(KeyShortcut(parsing: "Cmd+C+V"))
        XCTAssertNil(KeyShortcut(parsing: "Caps+C"))
        XCTAssertEqual(maccy.virtualKey, 8)
        XCTAssertEqual(KeyShortcut("V").virtualKey, 9)
        XCTAssertEqual(KeyShortcut("space").virtualKey, KeyPress.Code.space)
    }

    func testShortcutLabels() {
        XCTAssertEqual(KeyShortcut("k").label, "⌘K")
        XCTAssertEqual(KeyShortcut("c", shift: true, option: true).label, "⌥⇧⌘C")
        XCTAssertEqual(KeyShortcut(menuKey: "N", axModifiers: 1).label, "⇧⌘N")
        XCTAssertEqual(KeyShortcut(menuKey: "F", axModifiers: 8 | 4).label, "⌃F")
    }
}
