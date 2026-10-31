import XCTest
@testable import IcebergKit

/// The script contract (Waybar's custom module, plus Iceberg's icon and
/// colour) and the three widget modes: interval, signal and stream.
final class WidgetContractTests: XCTestCase {
    private func parse(_ text: String, _ name: String = "w.toml") -> (WidgetConfig?, [ConfigIssue]) {
        WidgetConfig.parse(Data(text.utf8), fileName: name)
    }

    // MARK: Output

    func testWaybarFields() {
        let d = CommandOutputParser.parse(#"{"text": "42%", "alt": "charging", "tooltip": "Battery\n2:10 left", "class": "warning", "percentage": 42}"#)
        XCTAssertEqual(d.text, "42%")
        XCTAssertEqual(d.alt, "charging")
        XCTAssertEqual(d.tooltip, "Battery\n2:10 left")
        XCTAssertEqual(d.classes, ["warning"])
        XCTAssertEqual(d.percentage, 42)
        // A class naming a theme colour colours the text.
        XCTAssertEqual(d.color, .theme(.yellow))
        XCTAssertFalse(d.failed)
    }

    func testClassListsAndColourPrecedence() {
        let d = CommandOutputParser.parse(#"{"text": "x", "class": ["muted-off", "critical"], "color": "blue"}"#)
        XCTAssertEqual(d.classes, ["muted-off", "critical"])
        XCTAssertEqual(d.color, .theme(.blue), "color wins over class")
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "x", "class": "a critical"}"#).color, .theme(.red))
        XCTAssertNil(CommandOutputParser.parse(#"{"text": "x", "class": "custom-thing"}"#).color)
    }

    func testPercentageIsKeptInRange() {
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "x", "percentage": 140}"#).percentage, 100)
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "x", "percentage": -3}"#).percentage, 0)
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "x", "percentage": "55"}"#).percentage, 55)
        XCTAssertNil(CommandOutputParser.parse(#"{"text": "x", "percentage": "lots"}"#).percentage)
    }

    func testPlainTextStillWorks() {
        let d = CommandOutputParser.parse("21°C\n")
        XCTAssertEqual(d, WidgetDisplay(text: "21°C"))
    }

    func testLastJSONLineWins() {
        let d = CommandOutputParser.parse("{\"text\": \"one\"}\n{\"text\": \"two\", \"icon\": \"tray\"}\n")
        XCTAssertEqual(d.text, "two")
        XCTAssertEqual(d.icon, "tray")
    }

    func testTooltipIsCleanedAndCut() {
        let long = String(repeating: "a", count: 2000)
        let d = CommandOutputParser.parse("{\"text\": \"x\", \"tooltip\": \"\\u001b[31m\(long)\"}")
        XCTAssertEqual(d.tooltip?.count, CommandOutputParser.maxTooltipLength)
        XCTAssertFalse(d.tooltip?.contains("\u{1B}") ?? true)
    }

    func testEmptyFieldsAreNil() {
        let d = CommandOutputParser.parse(#"{"text": "x", "alt": "", "tooltip": "  "}"#)
        XCTAssertNil(d.alt)
        XCTAssertNil(d.tooltip)
        XCTAssertEqual(d.classes, [])
        XCTAssertNil(d.percentage)
    }

    func testFailureReason() {
        var r = CommandResult()
        r.exitCode = 2
        r.stderr = "curl: (6) Could not resolve host\n"
        XCTAssertEqual(CommandOutputParser.failureReason(r), "curl: (6) Could not resolve host")
        r.stderr = ""
        XCTAssertEqual(CommandOutputParser.failureReason(r), "Command failed (exit 2)")
    }

    // MARK: Modes

    func testDefaultIsAnOnOpenPoll() throws {
        let w = try XCTUnwrap(parse("title = \"T\"\ncommand = \"date\"").0)
        XCTAssertEqual(w.mode, .poll(.onOpen))
        XCTAssertEqual(w.updates, .whenShown)
        XCTAssertFalse(w.always)
        XCTAssertFalse(w.runsWhileClosed)
    }

    func testSignalWidget() throws {
        let (w, issues) = parse("title = \"Mail\"\ncommand = \"./mail.sh\"\nsignal = true")
        XCTAssertEqual(issues, [])
        let config = try XCTUnwrap(w)
        XCTAssertTrue(config.signal)
        XCTAssertEqual(config.mode, .signal(.onOpen))
        let (w2, _) = parse("title = \"Mail\"\ncommand = \"./mail.sh\"\nsignal = true\nrefresh = \"10m\"")
        XCTAssertEqual(w2?.mode, .signal(.interval(600)))
    }

    func testStreamWidget() throws {
        let (w, issues) = parse("title = \"Volume\"\ncommand = \"./volume-watch.sh\"\nstream = true\nupdates = \"always\"\nalways = true")
        XCTAssertEqual(issues, [])
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.mode, .stream)
        XCTAssertTrue(config.runsWhileClosed)
        XCTAssertTrue(config.always)
    }

    func testStreamIgnoresSignalRefreshAndTimeout() throws {
        let (w, issues) = parse("""
        title = "S"
        command = "tail -f log"
        stream = true
        signal = true
        refresh = 60
        timeout = 5
        """)
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.mode, .stream)
        XCTAssertFalse(config.signal)
        XCTAssertEqual(issues.count, 3)
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning && $0.fix != nil && $0.line != nil })
    }

    func testUpdatesSpellings() throws {
        XCTAssertEqual(parse("command = \"x\"\ntitle = \"T\"\nupdates = \"when-shown\"").0?.updates, .whenShown)
        XCTAssertEqual(parse("command = \"x\"\ntitle = \"T\"\nupdates = \"Always\"").0?.updates, .always)
        let (w, issues) = parse("command = \"x\"\ntitle = \"T\"\nupdates = \"sometimes\"")
        XCTAssertEqual(w?.updates, .whenShown)
        XCTAssertEqual(issues.first?.line, 3)
        XCTAssertTrue(issues.first?.fix?.contains("when_shown") ?? false)
    }

    func testWaybarKeyNames() throws {
        let (w, issues) = parse("title = \"T\"\nexec = \"date\"\non-click = \"open .\"\ninterval = 30")
        XCTAssertEqual(issues, [])
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.command, "date")
        XCTAssertEqual(config.click, "open .")
        XCTAssertEqual(config.refresh, .interval(30))
    }

    func testJSONWidgetWithModes() throws {
        let (w, issues) = parse(#"{"title": "J", "command": "date", "signal": true, "always": true}"#, "j.json")
        XCTAssertEqual(issues, [])
        XCTAssertEqual(w?.mode, .signal(.onOpen))
        XCTAssertEqual(w?.always, true)
    }

    func testOlderFilesLoadAsBefore() throws {
        // A file written before the modes existed.
        let (w, issues) = parse("""
        title = "Disk"
        icon = "internaldrive"
        command = "df -h / | awk 'NR==2 {print $4}'"
        refresh = "5m"
        click = "open -a 'Disk Utility'"
        timeout = 3
        order = 2
        """)
        XCTAssertEqual(issues, [])
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.mode, .poll(.interval(300)))
        XCTAssertEqual(config.timeout, 3)
        XCTAssertEqual(config.order, 2)
    }

    func testModeDescriptions() {
        XCTAssertEqual(WidgetMode.poll(.interval(300)).description, "runs every 300 s")
        XCTAssertEqual(WidgetMode.signal(.onOpen).description, "runs on a signal and on open")
        XCTAssertEqual(WidgetMode.stream.description, "streams")
    }
}
