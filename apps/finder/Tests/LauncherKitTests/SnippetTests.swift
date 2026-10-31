import XCTest
@testable import LauncherKit

final class SnippetTests: XCTestCase {
    let file = """
    # Text shortcuts.
    matches:
      # Dates.
      - trigger: ";iso"
        replace: "{{d}}"
        vars: [{ name: d, type: date, params: { format: "%Y-%m-%d" } }]
      - trigger: ";ty"
        replace: "Thank you for your time and consideration."
      - triggers: [";ci", ";conf"]
        replace: '95% CI, it''s fine'
      - trigger: ";sig"
        label: Signature
        replace: |
          Best,
          Smith
      - trigger: ";when"
        replace: "Today is {{day}}"
        vars:
          - name: day
            type: date
            params:
              format: "%A, %B %-d"
      - trigger: ";sh"
        replace: "{{out}}"
        vars:
          - name: out
            type: shell
            params: { cmd: "date" }
    """

    func testYAMLShapes() {
        let value = MiniYAML.parse("a: 1\nb:\n  - x\n  - \"y z\"\nc: {k: [1, 2], s: 'q'}\nd: >\n  one\n  two\n")
        XCTAssertEqual(value?["a"]?.string, "1")
        XCTAssertEqual(value?["b"]?.array?.compactMap(\.string), ["x", "y z"])
        XCTAssertEqual(value?["c"]?["k"]?.array?.count, 2)
        XCTAssertEqual(value?["c"]?["s"]?.string, "q")
        XCTAssertEqual(value?["d"]?.string, "one two\n")
    }

    func testEscapesAndComments() {
        let value = MiniYAML.parse("a: \"line\\nnext \\\"q\\\"\"  \nb: plain # comment\n")
        XCTAssertEqual(value?["a"]?.string, "line\nnext \"q\"")
        XCTAssertEqual(value?["b"]?.string, "plain")
    }

    func testEspansoMatches() {
        let snippets = EspansoMatches.parse(file, file: "grand-line.yml", now: Make.noon, calendar: Make.toronto)
        XCTAssertEqual(snippets.map { $0.triggers[0] }, [";iso", ";ty", ";ci", ";sig", ";when", ";sh"])
        XCTAssertEqual(snippets[0].replace, "2026-10-31")
        XCTAssertEqual(snippets[2].triggers, [";ci", ";conf"])
        XCTAssertEqual(snippets[2].replace, "95% CI, it's fine")
        XCTAssertEqual(snippets[3].label, "Signature")
        XCTAssertEqual(snippets[3].replace, "Best,\nSmith\n")
        XCTAssertEqual(snippets[4].replace, "Today is Saturday, October 31")
        XCTAssertTrue(snippets[5].isDynamic)
        XCTAssertFalse(snippets[1].isDynamic)
    }

    func testSnippetRowsPasteOrTypeTheTrigger() {
        let rows = EspansoMatches.results(EspansoMatches.parse(file, file: "grand-line.yml", now: Make.noon, calendar: Make.toronto))
        XCTAssertEqual(rows[1].primary?.command, .paste("Thank you for your time and consideration."))
        XCTAssertEqual(rows[5].primary?.command, .typeText(";sh"))
        XCTAssertEqual(rows[3].title, "Signature")
        XCTAssertEqual(rows[0].aliases, ["iso"])
        let found = Catalog(rows).search("thank")
        XCTAssertEqual(found.first?.accessory, ";ty")
    }

    func testStrftime() {
        XCTAssertEqual(DateText.strftime("%B %-d, %Y", Make.noon, calendar: Make.toronto), "October 31, 2026")
        XCTAssertEqual(DateText.strftime("%H:%M %p %a %j %%", Make.noon, calendar: Make.toronto), "12:00 PM Sat 304 %")
    }

    func testLoadSkipsUnderscoreFiles() throws {
        let folder = try Make.folder()
        try Make.write("matches:\n  - trigger: \":a\"\n    replace: \"A\"\n", to: folder.appendingPathComponent("base.yml"))
        try Make.write("matches:\n  - trigger: \":b\"\n    replace: \"B\"\n", to: folder.appendingPathComponent("_off.yml"))
        try Make.write("matches:\n- trigger: \":c\"\n  replace: \"C\"\n", to: folder.appendingPathComponent("sub/more.yaml"))
        XCTAssertEqual(Set(EspansoMatches.load(folder: folder.path).map(\.replace)), ["A", "C"])
    }
}
