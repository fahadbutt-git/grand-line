import XCTest
@testable import IcebergKit

final class WidgetConfigTests: XCTestCase {
    private func parse(_ text: String, _ name: String = "sample.toml") -> (WidgetConfig?, [ConfigIssue]) {
        WidgetConfig.parse(Data(text.utf8), fileName: name)
    }

    func testFullTOMLWidget() throws {
        let (w, issues) = parse("""
        title = "Disk"
        icon = "internaldrive"
        command = "df -h / | awk 'NR==2 {print $4}'"
        refresh = "5m"
        click = "open -a 'Disk Utility'"
        timeout = 3
        order = -1
        """, "Disk Space.toml")
        let config = try XCTUnwrap(w)
        XCTAssertEqual(issues, [])
        XCTAssertEqual(config.id, "disk-space")
        XCTAssertEqual(config.title, "Disk")
        XCTAssertEqual(config.icon, "internaldrive")
        XCTAssertEqual(config.refresh, .interval(300))
        XCTAssertEqual(config.click, "open -a 'Disk Utility'")
        XCTAssertEqual(config.timeout, 3)
        XCTAssertEqual(config.order, -1)
        XCTAssertTrue(config.enabled)
    }

    func testJSONWidget() throws {
        let (w, issues) = parse(#"{"title": "Uptime", "icon": "clock", "command": "uptime", "refresh": 60, "enabled": true}"#, "uptime.json")
        let config = try XCTUnwrap(w)
        XCTAssertEqual(issues, [])
        XCTAssertEqual(config.refresh, .interval(60))
        XCTAssertEqual(config.icon, "clock")
    }

    func testDefaults() throws {
        let (w, issues) = parse(#"command = "echo hi""#, "hello.toml")
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.title, "hello")
        XCTAssertEqual(config.icon, WidgetConfig.defaultIcon)
        XCTAssertEqual(config.refresh, .onOpen)
        XCTAssertEqual(config.timeout, WidgetConfig.defaultTimeout)
        XCTAssertNil(config.click)
        XCTAssertEqual(issues.map(\.severity), [.warning]) // title missing
    }

    func testRefreshForms() {
        let cases: [(TOMLValue, RefreshPolicy?)] = [
            (.integer(30), .interval(30)),
            (.float(7.5), .interval(7.5)),
            (.string("45s"), .interval(45)),
            (.string("2m"), .interval(120)),
            (.string("1h"), .interval(3600)),
            (.string("1d"), .interval(86400)),
            (.string("1m30s"), .interval(90)),
            (.string("on open"), .onOpen),
            (.string("On-Open"), .onOpen),
            (.string("open"), .onOpen),
            (.string("soon"), nil),
            (.integer(0), nil),
            (.integer(-5), nil),
            (.bool(true), nil),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(RefreshPolicy.parse(value)?.0, expected, "\(value)")
        }
    }

    func testFastRefreshIsClamped() throws {
        let (w, issues) = parse("command = \"date\"\ntitle = \"Clock\"\nrefresh = 1")
        XCTAssertEqual(try XCTUnwrap(w).refresh, .interval(RefreshPolicy.minimumInterval))
        XCTAssertTrue(issues.contains { $0.message.contains("raised") })
    }

    func testTimeoutIsClamped() throws {
        let (w, _) = parse("command = \"date\"\ntitle = \"T\"\ntimeout = 900")
        XCTAssertEqual(try XCTUnwrap(w).timeout, 120)
        let (w2, _) = parse("command = \"date\"\ntitle = \"T\"\ntimeout = 0")
        XCTAssertEqual(try XCTUnwrap(w2).timeout, 1)
    }

    func testMissingCommandIsAnError() {
        let (w, issues) = parse("title = \"Nothing\"")
        XCTAssertNil(w)
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("command") })
    }

    func testWrongTypesAreReported() {
        let (w, issues) = parse("title = \"T\"\ncommand = 42")
        XCTAssertNil(w)
        XCTAssertTrue(issues.contains { $0.message.contains("must be text") })
    }

    func testUnknownKeysGetHints() throws {
        let (w, issues) = parse("title = \"T\"\ncommand = \"date\"\nrefesh = 60\ncolour = \"red\"")
        XCTAssertNotNil(w)
        XCTAssertTrue(issues.contains { $0.message.contains("did you mean \"refresh\"") })
        XCTAssertTrue(issues.contains { $0.message.contains("\"colour\"") })
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning })
    }

    func testAliases() throws {
        let (w, _) = parse("title = \"T\"\nscript = \"date\"\nsymbol = \"clock\"\non_click = \"open .\"\ninterval = 10")
        let config = try XCTUnwrap(w)
        XCTAssertEqual(config.command, "date")
        XCTAssertEqual(config.icon, "clock")
        XCTAssertEqual(config.click, "open .")
        XCTAssertEqual(config.refresh, .interval(10))
    }

    func testBadIconFallsBack() throws {
        let (w, issues) = parse("title = \"T\"\ncommand = \"date\"\nicon = \"Not A Symbol!\"")
        XCTAssertEqual(try XCTUnwrap(w).icon, WidgetConfig.defaultIcon)
        XCTAssertFalse(issues.isEmpty)
    }

    func testSyntaxErrorReportsLine() {
        let (w, issues) = parse("title = \"T\"\ncommand = \"date\n")
        XCTAssertNil(w)
        XCTAssertEqual(issues.first?.line, 2)
        XCTAssertEqual(issues.first?.description.hasPrefix("sample.toml, line 2:"), true)
    }

    func testJSONMustBeAnObject() {
        XCTAssertNil(parse("[1, 2]", "a.json").0)
        XCTAssertNil(parse("{not json", "b.json").0)
    }

    func testDurationParser() {
        XCTAssertEqual(RefreshPolicy.parseDuration("90"), 90)
        XCTAssertEqual(RefreshPolicy.parseDuration("1.5h"), 5400)
        XCTAssertNil(RefreshPolicy.parseDuration("5x"))
        XCTAssertNil(RefreshPolicy.parseDuration("m"))
        XCTAssertNil(RefreshPolicy.parseDuration("5m3"))
    }
}
