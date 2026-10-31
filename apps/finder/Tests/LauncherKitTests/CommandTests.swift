import XCTest
@testable import LauncherKit

final class CommandTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")

    func testReminderTimes() {
        let reminder = ReminderProvider(paths: paths, calendar: Make.toronto, now: { Make.noon })
        XCTAssertEqual(reminder.parse("call Smith in 20 min").text, "call Smith")
        XCTAssertEqual(reminder.parse("call Smith in 20 min").minutes, 20)
        XCTAssertEqual(reminder.parse("pay rent 2h").minutes, 120)
        XCTAssertEqual(reminder.parse("stretch 15").minutes, 15)
        XCTAssertEqual(reminder.parse("submit at 3pm").minutes, 180)
        // Tomorrow at 11, and Toronto's clocks go back an hour that night.
        XCTAssertEqual(reminder.parse("submit at 11am").minutes, 24 * 60)
        let plain = reminder.parse("buy 2 eggs")
        XCTAssertEqual(plain.text, "buy 2 eggs")
        XCTAssertEqual(plain.minutes, ReminderProvider.defaultMinutes)
        XCTAssertFalse(plain.given)
        let row = reminder.instantResults(for: LaunchQuery(raw: "!call Smith 20m", prefix: .reminder, term: "call Smith 20m")).first
        XCTAssertEqual(row?.primary?.command, .run("/Users/me/.grand-line/bin/reminder", arguments: ["call Smith", "20"]))
    }

    func testShellRunsInAWindow() {
        let row = ShellProvider(paths: paths).instantResults(for: LaunchQuery(raw: "> ls -la", prefix: .shell, term: "ls -la")).first
        XCTAssertEqual(row?.primary?.command, .run("/Users/me/.grand-line/bin/in-window", arguments: ["/bin/zsh", "-lc", "ls -la"]))
    }

    func testClipboardPressesMaccysShortcut() {
        let row = ClipboardProvider().instantResults(for: LaunchQuery(raw: "$", prefix: .clipboard, term: "")).first
        XCTAssertEqual(row?.primary?.command, .pressKeys(KeyShortcut("c", shift: true)))
        XCTAssertEqual(row?.primary?.closesWindow, true)
        XCTAssertEqual(row?.keys, ["⇧⌘C"])
        XCTAssertTrue(ClipboardProvider(keys: "Hyper+C").instantResults(for: LaunchQuery(raw: "$", prefix: .clipboard, term: "")).isEmpty)
    }

    func testPrefixListTypesThePrefix() {
        let provider = PrefixListProvider(keywords: [("z", "Zotero")])
        let all = provider.instantResults(for: LaunchQuery(raw: "/", prefix: .providers, term: ""))
        XCTAssertEqual(all.count, Prefix.allCases.count)
        let calc = provider.instantResults(for: LaunchQuery(raw: "/calc", prefix: .providers, term: "calc"))
        XCTAssertEqual(calc.first?.primary?.command, .setQuery("="))
        XCTAssertEqual(calc.first?.primary?.closesWindow, false)
    }

    func testAliasesToURLsAndPaths() {
        let provider = AliasProvider(paths: paths)
        provider.set(AliasTable.parse("drive\t~/Drive\nlab\thttps://example.org/lab\nff\tapp:/Applications/Firefox.app\n"))
        XCTAssertEqual(provider.aliases.standalone.map(\.alias), ["drive", "lab"])
        let drive = provider.instantResults(for: LaunchQuery(raw: "drive")).first
        XCTAssertEqual(drive?.primary?.command, .open("/Users/me/Drive"))
        XCTAssertEqual(drive?.match.alias, .exact)
        XCTAssertEqual(provider.instantResults(for: LaunchQuery(raw: "la")).first?.match.alias, .prefix)
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "ff")).isEmpty)
        XCTAssertEqual(provider.aliases.match(folded: "ff", id: "app:/Applications/Firefox.app", own: []), .exact)
    }

    func testShellQuoting() {
        XCTAssertEqual(ShellQuote.quote("plain-word"), "plain-word")
        XCTAssertEqual(ShellQuote.quote("it's here"), "'it'\\''s here'")
        XCTAssertEqual(ShellQuote.line(["open", "a b"]), "open 'a b'")
    }

    func testShellRunnerReadsOutputAndHonoursTimeout() async throws {
        let runner = ShellRunner()
        let out = try await runner.run("/bin/echo", ["hello"])
        XCTAssertEqual(out.stdout, "hello\n")
        XCTAssertEqual(out.status, 0)
        let started = Date()
        _ = try await runner.run("/bin/sleep", ["5"], timeout: 0.3)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testShellRunnerAnswersWhenAChildHoldsTheOutputOpen() async throws {
        // osascript waiting on a privacy prompt keeps the pipe open after the
        // command that started it is stopped; the row must still hear back.
        let runner = ShellRunner()
        let started = Date()
        let out = try await runner.run("/bin/sh", ["-c", "sleep 20 & wait"], timeout: 0.5)
        XCTAssertEqual(out.status, 15)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testShellRunnerStopsWhenCancelled() async {
        let runner = ShellRunner()
        let started = Date()
        let task = Task { try await runner.run("/bin/sleep", ["5"], timeout: 10) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let result = await task.result
        XCTAssertThrowsError(try result.get())
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }

    func testEnvironmentPutsGrandLineFirst() {
        let env = ShellRunner.environment(paths: paths, base: ["PATH": "/usr/bin:/bin"])
        XCTAssertTrue(env["PATH"]!.hasPrefix("/Users/me/.grand-line/bin:/opt/homebrew/bin"))
        XCTAssertEqual(env["LANG"], "en_US.UTF-8")
    }
}
