import XCTest
@testable import IcebergKit

final class CommandOutputTests: XCTestCase {
    private func result(_ out: String, exit: Int32 = 0, err: String = "") -> CommandResult {
        var r = CommandResult()
        r.stdout = out
        r.stderr = err
        r.exitCode = exit
        r.timeout = 10
        return r
    }

    func testFirstLine() {
        XCTAssertEqual(CommandOutputParser.parse("\n\n  21°C  \nsecond line\n").text, "21°C")
        XCTAssertEqual(CommandOutputParser.parse("").text, "")
    }

    func testJSONOutput() {
        let d = CommandOutputParser.parse(#"{"text": "3 new", "icon": "tray", "color": "highlight"}"#)
        XCTAssertEqual(d, WidgetDisplay(text: "3 new", icon: "tray", color: .theme(.highlight)))
    }

    func testJSONNumbersAndAliases() {
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": 42}"#).text, "42")
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": 4.5}"#).text, "4.5")
        XCTAssertEqual(CommandOutputParser.parse(#"{"label": "x"}"#).text, "x")
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "a", "color": "warning"}"#).color, .theme(.yellow))
        XCTAssertEqual(CommandOutputParser.parse(##"{"text": "a", "color": "#ff0000"}"##).color, .hex(RGB(red: 1, green: 0, blue: 0)))
        XCTAssertNil(CommandOutputParser.parse(#"{"text": "a", "color": "sparkly"}"#).color)
        XCTAssertNil(CommandOutputParser.parse(#"{"text": "a", "icon": "  "}"#).icon)
    }

    func testBrokenJSONIsShownAsText() {
        XCTAssertEqual(CommandOutputParser.parse(#"{"text": "unfinished"#).text, #"{"text": "unfinished"#)
    }

    func testANSIAndControlCharactersAreRemoved() {
        XCTAssertEqual(CommandOutputParser.parse("\u{1B}[1;32mgreen\u{1B}[0m\tok\u{07}").text, "green ok")
        XCTAssertEqual(CommandOutputParser.clean("\u{1B}]0;title\u{07}text"), "text")
    }

    func testLongTextIsCut() {
        let shown = CommandOutputParser.parse(String(repeating: "a", count: 500)).text
        XCTAssertEqual(shown.count, CommandOutputParser.maxLength)
        XCTAssertTrue(shown.hasSuffix("…"))
    }

    func testFailures() {
        let failed = CommandOutputParser.display(for: result("", exit: 2, err: "jq: not found\n"))
        XCTAssertTrue(failed.failed)
        XCTAssertEqual(failed.text, "jq: not found")

        let silent = CommandOutputParser.display(for: result("", exit: 3))
        XCTAssertEqual(silent.text, "Command failed (exit 3)")

        let withOutput = CommandOutputParser.display(for: result("partial\n", exit: 1))
        XCTAssertEqual(withOutput.text, "partial")
        XCTAssertTrue(withOutput.failed)

        var hung = CommandResult()
        hung.timedOut = true
        hung.timeout = 2
        XCTAssertEqual(CommandOutputParser.display(for: hung).text, "No answer after 2 s")

        var unstartable = CommandResult()
        unstartable.launchError = "Could not start"
        XCTAssertEqual(CommandOutputParser.display(for: unstartable).text, "Could not start")
    }

    func testColorNames() {
        XCTAssertEqual(WidgetColor.parse("RED"), .theme(.red))
        XCTAssertEqual(WidgetColor.parse("muted"), .theme(.muted))
        XCTAssertEqual(WidgetColor.parse("fff"), .hex(RGB(red: 1, green: 1, blue: 1)))
        XCTAssertNil(WidgetColor.parse("#12345"))
    }
}
