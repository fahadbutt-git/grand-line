import XCTest
@testable import BrowserKit

/// R4 and the rule that every action has a menu item with its shortcut.
final class KeyMapTests: XCTestCase {
    func testReturnOpensF2RenamesCommandUpGoesUp() {
        XCTAssertEqual(KeyMap.command(for: Shortcut(.returnKey)), .open)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.function(2))), .rename)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.up, .command)), .enclosingFolder)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.down, .command)), .openSelection)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.space)), .quickLook)
        XCTAssertEqual(KeyMap.command(for: .command("g", .shift)), .goToFolder)
        XCTAssertEqual(KeyMap.command(for: .command("x")), .cut)
    }

    func testPaneKeys() {
        XCTAssertEqual(KeyMap.command(for: Shortcut(.tab)), .nextPane)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.tab, .shift)), .previousPane)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.function(5))), .copyToNextPane)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.function(6))), .moveToNextPane)
    }

    /// Nexus's own tools sit on Control+Option, which Finder leaves free.
    func testToolKeys() {
        XCTAssertEqual(KeyMap.command(for: Shortcut(.character("t"), [.control, .option])), .openTerminal)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.character("a"), [.control, .option])), .openClaude)
        XCTAssertEqual(KeyMap.command(for: Shortcut(.character("3"), [.control, .option])), .transcodeJPEG)
        XCTAssertEqual(KeyMap.command(for: .command("c", .option)), .copyPath)
    }

    /// The owner's rule: Nexus never takes a Finder function away, so every
    /// Finder default shortcut means what it means in Finder.
    func testFinderShortcutsKeepTheirFinderMeaning() {
        func expect(_ shortcut: Shortcut, _ command: BrowserCommand) {
            XCTAssertEqual(KeyMap.command(for: shortcut), command, "\(shortcut) must stay \(command)")
        }
        expect(.command("n"), .newWindow)
        expect(.command("t"), .newTab)
        expect(.command("n", .shift), .newFolder)
        expect(.command("n", .control), .newFolderWithSelection)
        expect(.command("o"), .open)
        expect(.command("w"), .closeWindow)
        expect(.command("w", .option), .closeAllWindows)
        expect(.command("i"), .getInfo)
        expect(.command("d"), .duplicate)
        expect(.command("l"), .makeAlias)
        expect(.command("a", .control), .makeAlias)
        expect(.command("r"), .showOriginal)
        expect(.command("y"), .quickLook)
        expect(.command("y", .option), .fullScreenPreview)
        expect(Shortcut(.delete, .command), .moveToTrash)
        expect(Shortcut(.delete, [.command, .shift]), .emptyTrash)
        expect(.command("e"), .eject)
        expect(.command("f"), .find)
        expect(.command("t", .control), .addToSidebar)
        expect(.command("z"), .undo)
        expect(.command("z", .shift), .redo)
        expect(.command("x"), .cut)
        expect(.command("c"), .copy)
        expect(.command("v"), .paste)
        expect(.command("v", .option), .moveHere)
        expect(.command("a"), .selectAll)
        expect(.command("a", .option), .deselectAll)
        expect(.command("c", .option), .copyPath)
        expect(.command("1"), .viewIcons)
        expect(.command("2"), .viewList)
        expect(.command("3"), .viewColumns)
        expect(.command("4"), .viewGallery)
        expect(.command("j"), .showViewOptions)
        expect(.command(".", .shift), .toggleHidden)
        expect(.command("p", .shift), .togglePreview)
        expect(.command("i", .option), .toggleInspector)
        expect(.command("s", .option), .toggleSidebar)
        expect(.command("/"), .toggleStatusBar)
        expect(.command("t", .option), .toggleToolbar)
        expect(.command("p", .option), .togglePathBar)
        expect(.command("["), .back)
        expect(.command("]"), .forward)
        expect(Shortcut(.up, .command), .enclosingFolder)
        expect(Shortcut(.down, .command), .openSelection)
        expect(.command("f", .shift), .goRecents)
        expect(.command("o", .shift), .goDocuments)
        expect(.command("d", .shift), .goDesktop)
        expect(.command("l", .option), .goDownloads)
        expect(.command("h", .shift), .goHome)
        expect(.command("c", .shift), .goComputer)
        expect(.command("r", .shift), .goAirDrop)
        expect(.command("k", .shift), .goNetwork)
        expect(.command("i", .shift), .goICloud)
        expect(.command("a", .shift), .goApplications)
        expect(.command("u", .shift), .goUtilities)
        expect(.command("l", .shift), .goLibrary)
        expect(.command("g", .shift), .goToFolder)
        expect(.command("k"), .connectToServer)
        expect(.command("1", [.control, .option]), .sortName)
        expect(.command("2", [.control, .option]), .sortKind)
        expect(.command("5", [.control, .option]), .sortModified)
        expect(.command("6", [.control, .option]), .sortCreated)
        expect(.command("7", [.control, .option]), .sortSize)
        expect(.command("3", [.control, .option]), .sortLastOpened)
        expect(.command("4", [.control, .option]), .sortAdded)
        expect(.command("8", [.control, .option]), .sortTags)
        expect(Shortcut(.up, [.command, .control]), .enclosingFolderInNewWindow)
        expect(Shortcut(.delete, [.command, .shift, .option]), .emptyTrashNow)
    }

    /// macOS takes Control+Shift+Command+3 and 4 for screenshots before any app sees them.
    func testNoShortcutIsTakenBySystemScreenshots() {
        for spec in CommandCatalog.all {
            for shortcut in spec.shortcuts where shortcut.modifiers == [.command, .shift] || shortcut.modifiers == [.command, .shift, .control] {
                XCTAssertFalse(["3", "4", "5"].contains(shortcut.keyLabel), "\(spec.command) uses \(shortcut)")
            }
        }
    }

    /// While a field is edited, its keys are its own (renaming, search, the path bar).
    func testTextFieldsKeepTheirKeys() {
        XCTAssertEqual(BrowserCommand.copy.textAction, .copy)
        XCTAssertEqual(BrowserCommand.redo.textAction, .redo)
        XCTAssertNil(BrowserCommand.moveToTrash.textAction)
        XCTAssertTrue(Shortcut(.space).belongsToTextFields)
        XCTAssertTrue(Shortcut(.delete, .command).belongsToTextFields, "Cmd+Delete deletes to the line start")
        XCTAssertTrue(Shortcut(.up, .command).belongsToTextFields)
        XCTAssertFalse(Shortcut.command("e").belongsToTextFields)
        XCTAssertFalse(Shortcut(.character("t"), [.control, .option]).belongsToTextFields)
    }

    func testKeysThatChangeMeaningWithThePlace() {
        let delete = Shortcut(.delete, .command)
        XCTAssertEqual(KeyMap.command(for: delete), .moveToTrash)
        XCTAssertEqual(KeyMap.command(for: delete, inTrash: true), .putBack)
        XCTAssertEqual(KeyMap.command(for: .command("e")), .eject)
        XCTAssertEqual(KeyMap.command(for: .command("e"), inArchive: true), .extract)
    }

    func testNoTwoCommandsShareAKeyInTheSamePlace() {
        XCTAssertEqual(KeyMap.conflicts(), [:])
    }

    func testEveryCommandIsInTheMenuBarWithAShortcut() {
        let inMenus = MenuLayout.allCommands()
        for command in BrowserCommand.allCases {
            XCTAssertTrue(inMenus.contains(command), "\(command) has no menu item")
            XCTAssertFalse(CommandCatalog.spec(command).shortcuts.isEmpty, "\(command) has no shortcut")
        }
        XCTAssertEqual(Set(inMenus).count, inMenus.count, "each command appears once")
    }

    func testMenusHaveSubmenusAndSeparators() {
        let file = MenuLayout.entries(for: .file)
        let submenus = file.compactMap { entry -> String? in
            if case .submenu(let title, _) = entry { return title }
            return nil
        }
        XCTAssertEqual(submenus, ["Tags"])
        if case .separator? = file.first { XCTFail("a menu never starts with a separator") }
    }

    func testShortcutLabelsAndMenuKeys() {
        XCTAssertEqual(Shortcut.command("n", .shift).description, "⇧⌘N")
        XCTAssertEqual(Shortcut.command("1", [.control, .option]).description, "⌃⌥⌘1")
        XCTAssertEqual(Shortcut(.function(2)).description, "F2")
        XCTAssertEqual(Shortcut(.function(2)).menuKeyEquivalent.unicodeScalars.first?.value, 0xF705)
        XCTAssertEqual(Shortcut(.up, .command).menuKeyEquivalent.unicodeScalars.first?.value, 0xF700)
        XCTAssertEqual(Shortcut(.delete, .command).menuKeyEquivalent, "\u{8}")
        XCTAssertTrue(Shortcut(.space).isPlain)
        XCTAssertFalse(Shortcut.command("c").isPlain)
        XCTAssertEqual(Shortcut(.character("N"), .command), .command("n"))
    }

    func testKeyCodes() {
        XCTAssertEqual(Shortcut.from(keyCode: 36, characters: "\r", modifiers: []), Shortcut(.returnKey))
        XCTAssertEqual(Shortcut.from(keyCode: 120, characters: "", modifiers: []), Shortcut(.function(2)))
        XCTAssertEqual(Shortcut.from(keyCode: 96, characters: "", modifiers: []), Shortcut(.function(5)))
        XCTAssertEqual(Shortcut.from(keyCode: 126, characters: "", modifiers: .command), Shortcut(.up, .command))
        XCTAssertEqual(Shortcut.from(keyCode: 48, characters: "\t", modifiers: .shift), Shortcut(.tab, .shift))
        XCTAssertEqual(Shortcut.from(keyCode: 0, characters: "a", modifiers: []), Shortcut(.character("a")))
    }

    func testFooterHints() {
        let plain = FooterHints.hints(inArchive: false, inTrash: false, paneCount: 1, searching: false)
        XCTAssertEqual(plain.map(\.label), ["open", "rename", "preview", "up", "path", "search"])
        let panes = FooterHints.hints(inArchive: false, inTrash: false, paneCount: 3, searching: false)
        XCTAssertTrue(panes.contains(FooterHint("F5", "copy")))
        XCTAssertTrue(panes.contains(FooterHint("Tab", "next pane")))
        let archive = FooterHints.hints(inArchive: true, inTrash: false, paneCount: 2, searching: false)
        XCTAssertTrue(archive.contains(FooterHint("⌘E", "extract")))
        let trash = FooterHints.hints(inArchive: false, inTrash: true, paneCount: 1, searching: false)
        XCTAssertEqual(trash.first, FooterHint("⌘⌫", "put back"))
    }
}
