import XCTest
@testable import DenDenKit

/// Den Den must stay calm with many widgets, hung commands and junk files.
final class StressTests: XCTestCase {
    private func pad(_ i: Int) -> String { i < 10 ? "0\(i)" : "\(i)" }

    func testFiftyWidgetsLoadAndRunWithLimitedConcurrency() throws {
        let tmp = TempFolder()
        for i in 1...50 {
            let ext = i % 2 == 0 ? "toml" : "json"
            if ext == "toml" {
                tmp.write("w" + pad(i) + ".toml", "title = \"W\(i)\"\ncommand = \"sleep 0.05; echo value-\(i)\"\nrefresh = \(5 + i)\norder = \(i)")
            } else {
                tmp.write("w" + pad(i) + ".json", #"{"title": "W\#(i)", "command": "echo '{\"text\": \"value-\#(i)\"}'", "order": \#(i)}"#)
            }
        }
        let loaded = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(loaded.widgets.count, 50)
        XCTAssertEqual(loaded.issues, [])
        XCTAssertEqual(loaded.widgets.map(\.order), Array(1...50))

        let scheduler = RefreshScheduler()
        scheduler.setWidgets(loaded.widgets.map { (id: $0.id, policy: $0.refresh) })
        let due = scheduler.panelOpened(at: Date())
        XCTAssertEqual(due.count, 50)

        let pool = CommandPool(maxConcurrent: 4)
        let collected = Collector<String>()
        let started = Date()
        for w in loaded.widgets where due.contains(w.id) {
            pool.submit(id: w.id, command: w.command, timeout: w.timeout, workingDirectory: tmp.url) { id, result in
                collected.set(id, CommandOutputParser.display(for: result).text)
            }
        }
        pool.waitUntilIdle()
        let shown = collected.values
        XCTAssertEqual(shown.count, 50)
        for i in 1...50 {
            XCTAssertEqual(shown["w" + pad(i)], "value-\(i)")
        }
        XCTAssertLessThanOrEqual(pool.peakConcurrency, 4)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
    }

    func testSameWidgetIsNeverRunTwiceAtOnce() {
        let pool = CommandPool(maxConcurrent: 4)
        XCTAssertTrue(pool.submit(id: "a", command: "sleep 0.3", timeout: 2) { _, _ in })
        XCTAssertTrue(pool.isBusy("a"))
        XCTAssertFalse(pool.submit(id: "a", command: "sleep 0.3", timeout: 2) { _, _ in })
        pool.waitUntilIdle()
        XCTAssertFalse(pool.isBusy("a"))
        XCTAssertTrue(pool.submit(id: "a", command: "true", timeout: 2) { _, _ in })
        pool.waitUntilIdle()
    }

    func testHungWidgetsDoNotHoldUpTheOthers() {
        let pool = CommandPool(maxConcurrent: 4)
        let collected = Collector<CommandResult>()
        let started = Date()
        for i in 0..<4 {
            pool.submit(id: "hang\(i)", command: "sleep 60", timeout: 1) { id, r in
                collected.set(id, r)
            }
        }
        for i in 0..<8 {
            pool.submit(id: "ok\(i)", command: "echo fine", timeout: 5) { id, r in
                collected.set(id, r)
            }
        }
        pool.waitUntilIdle()
        let results = collected.values
        let took = Date().timeIntervalSince(started)
        XCTAssertLessThan(took, 6, "took \(took) s")
        for i in 0..<4 {
            XCTAssertEqual(results["hang\(i)"]?.timedOut, true)
            XCTAssertEqual(CommandOutputParser.display(for: results["hang\(i)"]!).failed, true)
        }
        for i in 0..<8 { XCTAssertEqual(results["ok\(i)"]?.stdout, "fine\n") }
    }

    func testMalformedConfigsAreReportedNotCrashedOn() {
        let tmp = TempFolder()
        let junk: [(String, String)] = [
            ("empty.toml", ""),
            ("only-comment.toml", "# nothing here"),
            ("unclosed.toml", "title = \"x\ncommand = \"y\""),
            ("no-equals.toml", "title \"x\""),
            ("wrong-type.toml", "title = 5\ncommand = [\"a\"]"),
            ("inline.toml", "command = { run = \"x\" }"),
            ("array-tables.toml", "[[widget]]\ncommand = \"x\""),
            ("duplicate.toml", "command = \"a\"\ncommand = \"b\""),
            ("deep.toml", "command = " + String(repeating: "[", count: 500)),
            ("escape.toml", "command = \"\\x\""),
            ("unicode.toml", "command = \"\\uZZZZ\""),
            ("bad.json", "{\"command\": "),
            ("array.json", "[]"),
            ("null.json", "null"),
            ("nested.json", #"{"command": {"a": 1}}"#),
            ("string.json", #""just text""#),
            ("deep.json", String(repeating: "[", count: 5000)),
            ("refresh.toml", "command = \"x\"\nrefresh = \"whenever\""),
        ]
        for (name, text) in junk { tmp.write(name, text) }
        tmp.write("binary.toml", data: Data([0xFF, 0xFE, 0x00, 0x80, 0xC3]))
        tmp.write("huge.toml", String(repeating: "# filler line\n", count: 10_000))
        tmp.write("fine.toml", "title = \"Fine\"\ncommand = \"echo ok\"")

        let r = WidgetLoader.load(from: tmp.url)
        // The good file and the one with only a bad refresh still load.
        XCTAssertEqual(Set(r.widgets.map(\.id)), ["fine", "refresh"])
        let reported = Set(r.issues.map(\.file))
        for (name, _) in junk where name != "refresh.toml" {
            XCTAssertTrue(reported.contains(name), "\(name) was not reported")
        }
        XCTAssertTrue(reported.contains("binary.toml"))
        XCTAssertTrue(reported.contains("huge.toml"))
        XCTAssertTrue(r.issues.allSatisfy { !$0.message.isEmpty })
    }

    func testRandomBytesNeverCrashTheParsers() {
        var generator = SystemRandomNumberGenerator()
        let alphabet = Array("ab=\"'[]{}#.,\n\\ 0123x-_tf\u{1B}")
        for _ in 0..<500 {
            let length = Int.random(in: 0..<120, using: &generator)
            let text = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
            _ = try? TOML.parse(text)
            _ = WidgetConfig.parse(Data(text.utf8), fileName: "fuzz.toml")
            _ = WidgetConfig.parse(Data(text.utf8), fileName: "fuzz.json")
            _ = CommandOutputParser.parse(text)
            _ = DenDenSettings.parse(text)
            _ = ThemeLoader.parse(text, name: "fuzz")
            var state = NowPlayingState()
            state.apply(line: text)
        }
    }

    func testFloodOfOutputIsCapped() {
        let r = CommandRunner().run("yes 0123456789 | head -c 5000000", timeout: 10)
        XCTAssertLessThanOrEqual(r.stdout.utf8.count, CommandRunner().maxOutputBytes)
        XCTAssertTrue(r.truncated)
        XCTAssertEqual(CommandOutputParser.display(for: r).text, "0123456789")
    }
}
