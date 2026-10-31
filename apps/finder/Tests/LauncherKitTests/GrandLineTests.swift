import XCTest
@testable import LauncherKit

final class GrandLineTests: XCTestCase {
    let shipped = """
    # Main menu
    Apps/Open an app\tmenu-apps
    Toggle/Dark mode\ttoggle dark\t\t✓is_on dark
    Toggle/Bluetooth\ttoggle bluetooth\t?command -v blueutil\t✓is_on bluetooth
    Capture/Screenshot of an area\tcapture area
    """

    func testMenuEntriesWithGuardsAndChecks() {
        let entries = MenuFile.parse([shipped])
        XCTAssertEqual(entries.map(\.path), ["Apps/Open an app", "Toggle/Dark mode", "Toggle/Bluetooth", "Capture/Screenshot of an area"])
        XCTAssertEqual(entries[1].checkTest, "is_on dark")
        XCTAssertNil(entries[1].guardTest)
        XCTAssertEqual(entries[2].guardTest, "command -v blueutil")
        XCTAssertEqual(entries[2].label, "Bluetooth")
        XCTAssertEqual(entries[2].groups, ["Toggle"])
    }

    func testLocalMenuReplacesAndRemoves() {
        let local = "Apps/Open an app\tmy-apps\nCapture/Screenshot of an area\t-\nMine/Lab notes\topen ~/Drive/Lab\n"
        let entries = MenuFile.parse([shipped, local])
        XCTAssertEqual(entries.first?.command, "my-apps")
        XCTAssertFalse(entries.contains { $0.path == "Capture/Screenshot of an area" })
        XCTAssertEqual(entries.last?.path, "Mine/Lab notes")
    }

    func testProbeScriptAndStates() {
        let entries = MenuFile.parse([shipped])
        let script = MenuStateProbe.script(for: entries, helpers: "/Users/me/.grand-line/lib/toggle-state.sh")
        XCTAssertTrue(script.hasPrefix("source /Users/me/.grand-line/lib/toggle-state.sh"))
        XCTAssertTrue(script.contains("{ command -v blueutil; }"))
        let states = MenuStateProbe.parse("10\n11\n00\n10\n", entries: entries)
        XCTAssertEqual(states.map(\.shown), [true, true, false, true])
        XCTAssertEqual(states.map(\.checked), [false, true, false, false])
        let rows = MenuProvider.results(entries, states: states)
        XCTAssertEqual(rows.map(\.title), ["Open an app", "Dark mode", "Screenshot of an area"])
        XCTAssertEqual(rows[1].accessory, "On")
        XCTAssertEqual(rows[1].subtitle, "Toggle")
        XCTAssertEqual(rows[1].primary?.command, .shell("toggle dark"))
    }

    func testBeforeTheProbeGuardedEntriesStayHidden() {
        let entries = MenuFile.parse([shipped])
        XCTAssertFalse(MenuProvider.results(entries, states: nil).contains { $0.title == "Bluetooth" })
        XCTAssertEqual(MenuStateProbe.parse("", entries: entries).map(\.shown), [true, true, false, true])
    }

    func testMenuLinesRunThroughBinCommon() {
        let args = ShellRunner.bashArguments(for: "toggle dark", paths: GrandLinePaths(home: "/Users/me"))
        XCTAssertEqual(args.last, "toggle dark")
        XCTAssertTrue(args.contains("/Users/me/.grand-line/lib/bin-common.sh"))
    }

    func testCommandSummaryAndArguments() {
        let text = """
        #!/bin/bash
        # grandline:summary=Set a reminder in Apple Reminders
        # grandline:arg1={"type":"text","placeholder":"remind me to"}
        # grandline:arg2={"type":"text","placeholder":"in minutes","optional":true}
        source x
        """
        let script = CommandScript.parse(text, name: "reminder", path: "/b/reminder")!
        XCTAssertEqual(script.summary, "Set a reminder in Apple Reminders")
        XCTAssertEqual(script.arguments.count, 2)
        XCTAssertTrue(script.arguments[1].optional)
        XCTAssertEqual(script.usage, "reminder ‹remind me to›, ‹in minutes›")
        XCTAssertNil(CommandScript.parse("#!/bin/bash\necho hi\n", name: "x", path: "/x"))
    }

    func testArgumentSplitting() {
        XCTAssertEqual(ArgumentSplitter.split("buy milk, 30", count: 2), ["buy milk", "30"])
        XCTAssertEqual(ArgumentSplitter.split("buy milk", count: 2), ["buy milk"])
        XCTAssertEqual(ArgumentSplitter.split("\"a, b\", c", count: 2), ["a, b", "c"])
        XCTAssertEqual(ArgumentSplitter.split("one, two", count: 1), ["one, two"])
        XCTAssertEqual(ArgumentSplitter.split("a, b, c", count: 2), ["a", "b, c"])
    }

    func testDropdownArgumentsListTheirChoices() {
        let script = CommandScript(name: "transcode", path: "/b/transcode", summary: "Convert",
                                   arguments: [ArgumentSpec(type: .dropdown, placeholder: "to", data: ["video", "png", "jpeg", "pdf", "text"])])
        XCTAssertEqual(CommandsProvider.invocation(script, text: "").map(\.title), ["video", "png", "jpeg", "pdf", "text"])
        let p = CommandsProvider.invocation(script, text: "p")
        XCTAssertEqual(p.map(\.title), ["png", "pdf"])
        XCTAssertEqual(p[0].primary?.command, .run("/b/transcode", arguments: ["png"]))
    }

    func testTypedCommandShowsWhatWillRun() {
        let provider = CommandsProvider(folder: "/nowhere")
        let reminder = CommandScript(name: "reminder", path: "/b/reminder", summary: "Set a reminder",
                                     arguments: [ArgumentSpec(type: .text, placeholder: "remind me to"), ArgumentSpec(type: .text, placeholder: "in minutes", optional: true)])
        provider.replace([reminder, CommandScript(name: "update", path: "/b/update", summary: "Update everything", arguments: [])])
        let rows = provider.instantResults(for: LaunchQuery(raw: "reminder call Smith, 20"))
        XCTAssertEqual(rows.first?.primary?.command, .run("/b/reminder", arguments: ["call Smith", "20"]))
        let listed = provider.instantResults(for: LaunchQuery(raw: "upd"))
        XCTAssertEqual(listed.first?.title, "update")
        XCTAssertEqual(listed.first?.primary?.command, .run("/b/update", arguments: []))
        let found = provider.instantResults(for: LaunchQuery(raw: "everything"))
        XCTAssertEqual(found.first?.match.keyword, .wordStart)
    }

    func testCommandScanReadsExecutables() throws {
        let folder = try Make.folder()
        let file = folder.appendingPathComponent("hello")
        try Make.write("#!/bin/bash\n# grandline:summary=Say hello\n", to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        try Make.write("#!/bin/bash\n# grandline:summary=Not executable\n", to: folder.appendingPathComponent("plain"))
        XCTAssertEqual(CommandScript.scan(folder.path).map(\.name), ["hello"])
    }

    func testKeybindingsMergeLocalAndShowCaps() {
        let shipped = "# Generated\tGroup\tWhat\tCommand\nCaps + Space\tMenus\tSearch\t\nCaps + Option + Space\tMenus\tMain menu\t$HOME/.grand-line/bin/menu\nCaps + W\tWindows\tClose window\t\n"
        let local = "Caps + W\tWindows\tMy close\techo hi\nunbind\tCaps + Space\nCaps + Shift + L\tMine\tLab\topen -a Lab\n"
        let list = KeybindingsFile.parse(shipped, local: local)
        XCTAssertEqual(list.map(\.description), ["Main menu", "My close", "Lab"])
        XCTAssertEqual(list[0].caps, ["⇪", "⌥", "Space"])
        let rows = KeybindingsFile.results(list)
        XCTAssertEqual(rows[0].primary?.command, .shell("$HOME/.grand-line/bin/menu"))
        XCTAssertEqual(rows[0].keys, ["⇪", "⌥", "Space"])
        XCTAssertEqual(KeybindingsFile.results(KeybindingsFile.parse("Caps + W\tWindows\tClose window\t\n"))[0].primary?.title, "Copy keys")
    }

    func testAppsScanTwoLevelsAndOpenThroughFocusOrOpen() throws {
        let root = try Make.folder()
        for path in ["Safari.app/Contents", "Utilities/Terminal.app/Contents", "Vendor/Deep/Hidden.app", "Notes.txt"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        let apps = AppCatalog.scan([root.path])
        XCTAssertEqual(apps.map { ($0 as NSString).lastPathComponent }, ["Safari.app", "Terminal.app"])
        let row = AppCatalog.result(apps[0], paths: GrandLinePaths(home: "/Users/me"))
        XCTAssertEqual(row.title, "Safari")
        XCTAssertEqual(row.primary?.command, .run("/Users/me/.grand-line/bin/focus-or-open", arguments: ["Safari"]))
        XCTAssertEqual(row.secondary?.command, .reveal(apps[0]))
    }
}
