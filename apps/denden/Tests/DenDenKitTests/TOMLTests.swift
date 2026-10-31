import XCTest
@testable import DenDenKit

final class TOMLTests: XCTestCase {
    func testScalarsAndComments() throws {
        let t = try TOML.parse("""
        # a comment
        title = "Team sync"   # trailing comment
        count = 1_000
        hex = 0x1F
        ratio = 2.5
        on = true
        off = false
        literal = 'C:\\path'
        """)
        XCTAssertEqual(t["title"], .string("Team sync"))
        XCTAssertEqual(t["count"], .integer(1000))
        XCTAssertEqual(t["hex"], .integer(31))
        XCTAssertEqual(t["ratio"], .float(2.5))
        XCTAssertEqual(t["on"], .bool(true))
        XCTAssertEqual(t["off"], .bool(false))
        XCTAssertEqual(t["literal"], .string("C:\\path"))
    }

    func testEscapes() throws {
        let t = try TOML.parse(#"s = "tab\tquote\" back\\ \u00e9""#)
        XCTAssertEqual(t["s"], .string("tab\tquote\" back\\ é"))
    }

    func testMultilineStrings() throws {
        let t = try TOML.parse("""
        a = \"\"\"
        line one
        line two\"\"\"
        b = '''
        raw $HOME \\n'''
        c = \"\"\"joined \\
            here\"\"\"
        """)
        XCTAssertEqual(t["a"], .string("line one\nline two"))
        XCTAssertEqual(t["b"], .string("raw $HOME \\n"))
        XCTAssertEqual(t["c"], .string("joined here"))
    }

    func testArraysAcrossLines() throws {
        let t = try TOML.parse("""
        list = [
          "today",   # first
          "battery",
        ]
        nums = [1, 2.5, true]
        empty = []
        """)
        XCTAssertEqual(t["list"], .array([.string("today"), .string("battery")]))
        XCTAssertEqual(t["nums"], .array([.integer(1), .float(2.5), .bool(true)]))
        XCTAssertEqual(t["empty"], .array([]))
    }

    func testTablesAndDottedKeys() throws {
        let t = try TOML.parse("""
        top = 1
        [panel]
        size = 2
        "quoted key" = 3
        [panel.inner]
        a.b = 4
        """)
        XCTAssertEqual(t["top"], .integer(1))
        XCTAssertEqual(t["panel.size"], .integer(2))
        XCTAssertEqual(t["panel.quoted key"], .integer(3))
        XCTAssertEqual(t["panel.inner.a.b"], .integer(4))
    }

    func testWindowsLineEndingsAndBOM() throws {
        let t = try TOML.parse("\u{FEFF}a = 1\r\nb = \"x\"\r\n")
        XCTAssertEqual(t["a"], .integer(1))
        XCTAssertEqual(t["b"], .string("x"))
    }

    func testErrorsCarryLineNumbers() {
        let cases: [(String, Int, String)] = [
            ("a = 1\nb = \"open", 2, "not closed"),
            ("a = 1\na = 2", 2, "appears twice"),
            ("x = hello", 1, "needs quotes"),
            ("\n\nkey", 3, "expected \"=\""),
            ("t = { a = 1 }", 1, "inline tables"),
            ("[[items]]", 1, "arrays of tables"),
            ("d = 2026-01-02", 1, "dates"),
            ("a = [1, 2", 1, "not closed"),
            ("a = 1 2", 1, "new line"),
            ("s = \"bad \\q\"", 1, "unknown escape"),
            ("= 3", 1, "expected a key"),
            ("[t]\n[t]", 2, "twice"),
        ]
        for (text, line, fragment) in cases {
            XCTAssertThrowsError(try TOML.parse(text), text) { error in
                guard let e = error as? TOMLError else { return XCTFail("\(error)") }
                XCTAssertEqual(e.line, line, text)
                XCTAssertTrue(e.message.contains(fragment), "\(text): \(e.message)")
            }
        }
    }
}
