import XCTest
@testable import IcebergKit

/// Hot reload (what a save changes) and the per-widget diagnostics.
final class ReloadTests: XCTestCase {
    func testABrokenSaveKeepsTheLastGoodWidget() throws {
        let tmp = TempFolder()
        tmp.write("clock.toml", "title = \"Clock\"\ncommand = \"date +%H:%M\"")
        tmp.write("disk.toml", "title = \"Disk\"\ncommand = \"df -h\"")
        let first = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(first.failed, [:])

        // Half-way through an edit: the file does not parse.
        tmp.write("clock.toml", "title = \"Clock\"\ncommand = \"date +%H:%M")
        let broken = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(broken.failed, ["clock": "clock.toml"])
        let merged = WidgetReload.keepLastGood(previous: first.widgets, loaded: broken)
        XCTAssertEqual(merged.kept, ["clock"])
        XCTAssertEqual(Set(merged.widgets.map(\.id)), ["clock", "disk"])
        XCTAssertEqual(merged.widgets.first { $0.id == "clock" }?.command, "date +%H:%M")

        // Fixed: the new version is used.
        tmp.write("clock.toml", "title = \"Clock\"\ncommand = \"date +%H:%M:%S\"")
        let fixed = WidgetLoader.load(from: tmp.url)
        let again = WidgetReload.keepLastGood(previous: merged.widgets, loaded: fixed)
        XCTAssertEqual(again.kept, [])
        XCTAssertEqual(again.widgets.first { $0.id == "clock" }?.command, "date +%H:%M:%S")
        XCTAssertEqual(WidgetReload.changed(from: merged.widgets, to: again.widgets), ["clock"])
    }

    func testDeletedFileIsNotKept() {
        let tmp = TempFolder()
        tmp.write("a.toml", "title = \"A\"\ncommand = \"echo a\"")
        let first = WidgetLoader.load(from: tmp.url)
        try? FileManager.default.removeItem(at: tmp.url.appendingPathComponent("a.toml"))
        let merged = WidgetReload.keepLastGood(previous: first.widgets, loaded: WidgetLoader.load(from: tmp.url))
        XCTAssertEqual(merged.widgets, [])
    }

    func testTurnedOffInItsFileIsNotKept() {
        let tmp = TempFolder()
        tmp.write("a.toml", "title = \"A\"\ncommand = \"echo a\"")
        let first = WidgetLoader.load(from: tmp.url)
        tmp.write("a.toml", "title = \"A\"\ncommand = \"echo a\"\nenabled = false")
        let merged = WidgetReload.keepLastGood(previous: first.widgets, loaded: WidgetLoader.load(from: tmp.url))
        XCTAssertEqual(merged.widgets, [])
    }

    func testChangedWidgets() {
        let a = WidgetConfig(id: "a", title: "A", command: "echo a")
        let b = WidgetConfig(id: "b", title: "B", command: "echo b")
        var b2 = b
        b2.refresh = .interval(60)
        let c = WidgetConfig(id: "c", title: "C", command: "echo c")
        XCTAssertEqual(WidgetReload.changed(from: [a, b], to: [a, b2, c]), ["b", "c"])
        XCTAssertEqual(WidgetReload.changed(from: [a], to: [a]), [])
    }

    func testSavedScriptsRerunTheirWidgets() {
        let weather = WidgetConfig(id: "weather", title: "W", command: "./weather.sh")
        let services = WidgetConfig(id: "services", title: "S", command: "./services.sh", click: "./toggle.sh")
        let clock = WidgetConfig(id: "clock", title: "C", command: "date")
        let all = [weather, services, clock]
        XCTAssertEqual(WidgetReload.affected(byChangedFiles: ["weather.sh"], widgets: all), ["weather"])
        XCTAssertEqual(WidgetReload.affected(byChangedFiles: ["toggle.sh"], widgets: all), ["services"])
        XCTAssertEqual(WidgetReload.affected(byChangedFiles: ["weather.toml", ".weather.sh.swp"], widgets: all), [])
        XCTAssertEqual(WidgetReload.affected(byChangedFiles: [], widgets: all), [])
    }
}

final class DiagnosticsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 4_000_000)

    private func result(_ out: String, exit: Int32 = 0, err: String = "", duration: TimeInterval = 0.2) -> CommandResult {
        var r = CommandResult()
        r.stdout = out
        r.stderr = err
        r.exitCode = exit
        r.duration = duration
        r.timeout = 10
        return r
    }

    func testRunsAndAverage() {
        var s = WidgetStats()
        XCTAssertNil(s.averageRuntime)
        let ok = result("21°C\n", duration: 0.2)
        s.record(ok, display: CommandOutputParser.display(for: ok), at: t0)
        let ok2 = result("\u{1B}[32m22°C\u{1B}[0m\n", duration: 0.4)
        s.record(ok2, display: CommandOutputParser.display(for: ok2), at: t0.addingTimeInterval(60))
        XCTAssertEqual(s.runs, 2)
        XCTAssertEqual(s.averageRuntime ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(s.lastOutput, "22°C")
        XCTAssertEqual(s.lastRun, t0.addingTimeInterval(60))
        XCTAssertNil(s.lastError)
        XCTAssertEqual(s.summary, "2 runs, 0.30 s on average")
    }

    func testFailuresAndTimeouts() {
        var s = WidgetStats()
        let bad = result("", exit: 7, err: "curl: (7) Failed to connect\n")
        s.record(bad, display: CommandOutputParser.display(for: bad), at: t0)
        XCTAssertEqual(s.lastError, "curl: (7) Failed to connect")
        XCTAssertEqual(s.lastErrorAt, t0)
        XCTAssertEqual(s.failures, 1)

        var hung = CommandResult()
        hung.timedOut = true
        hung.timeout = 2
        hung.duration = 2.5
        s.record(hung, display: CommandOutputParser.display(for: hung), at: t0.addingTimeInterval(5))
        XCTAssertEqual(s.timeouts, 1)
        XCTAssertEqual(s.lastError, "No answer after 2 s")

        let partial = result("half\n", exit: 1)
        s.record(partial, display: CommandOutputParser.display(for: partial), at: t0.addingTimeInterval(9))
        XCTAssertEqual(s.lastError, "half (exit 1)")
        XCTAssertEqual(s.lastOutput, "half")
        s.recordSkip()
        XCTAssertTrue(s.summary.contains("3 failures"))
        XCTAssertTrue(s.summary.contains("1 timed out"))
        XCTAssertTrue(s.summary.contains("1 held back"))
    }

    func testOutputIsCut() {
        var s = WidgetStats()
        let many = result((1...20).map { "line \($0)" }.joined(separator: "\n"))
        s.record(many, display: CommandOutputParser.display(for: many), at: t0)
        XCTAssertEqual(s.lastOutput?.split(separator: "\n").count, 5)
        let huge = result(String(repeating: "x", count: 5000))
        s.record(huge, display: CommandOutputParser.display(for: huge), at: t0)
        XCTAssertEqual(s.lastOutput?.count, WidgetStats.maxOutputLength)
    }

    func testStreams() {
        var s = WidgetStats()
        s.recordStreamStart(at: t0)
        s.recordStreamLine(#"{"text": "50%"}"#, at: t0)
        s.recordStreamLine(#"{"text": "55%"}"#, at: t0)
        var stopped = StreamExit()
        stopped.stoppedByRequest = true
        stopped.duration = 30
        s.recordStreamExit(stopped, at: t0)
        XCTAssertEqual(s.failures, 0, "a stream Iceberg stopped did not fail")
        XCTAssertEqual(s.streamLines, 2)
        XCTAssertEqual(s.lastOutput, #"{"text": "55%"}"#)
        var crashed = StreamExit()
        crashed.exitCode = 1
        crashed.stderrTail = "pactl: not found\n"
        s.recordStreamExit(crashed, at: t0)
        XCTAssertEqual(s.failures, 1)
        XCTAssertEqual(s.lastError, "pactl: not found (exit 1)")
        XCTAssertEqual(s.streamStarts, 1)
    }
}
