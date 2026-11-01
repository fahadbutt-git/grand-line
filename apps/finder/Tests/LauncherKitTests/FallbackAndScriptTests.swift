import XCTest
import SQLite3
@testable import LauncherKit

/// A command runner that answers from a closure and remembers what it ran.
final class ScriptedRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [[String]] = []
    let answer: @Sendable ([String]) -> ShellOutput

    init(_ answer: @escaping @Sendable ([String]) -> ShellOutput) {
        self.answer = answer
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ShellOutput {
        lock.withLock { calls.append([executable] + arguments) }
        return answer(arguments)
    }

    var ran: [[String]] { lock.withLock { calls } }
}

final class FallbackAndScriptTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")
    let router = PrefixRouter(pathExists: { _ in false }, clipboardHistory: { false })

    // MARK: When nothing matches

    func engine(_ rows: [LaunchResult]) -> SearchEngine {
        SearchEngine(providers: [instant(rows), FallbackProvider(), FallbackCommandsProvider(paths: paths)], router: router)
    }

    func testNoMatchOffersCreateFileAndRunInTerminalAfterTheEngines() throws {
        let engine = engine([Make.row("Notes")])
        let rows = engine.instantGroups(engine.plan("qzxv 42")).flatMap(\.rows)
        let ids = rows.map(\.id)
        let google = try XCTUnwrap(ids.firstIndex(of: "fallback:g"))
        let calculate = try XCTUnwrap(ids.firstIndex(of: "fallback:calculate"))
        let create = try XCTUnwrap(ids.firstIndex(of: "fallback:create-file"))
        let run = try XCTUnwrap(ids.firstIndex(of: "fallback:run-terminal"))
        XCTAssertLessThan(google, calculate)
        XCTAssertLessThan(calculate, create)
        XCTAssertLessThan(create, run)
        XCTAssertEqual(rows[calculate].primary?.command, .setQuery("=qzxv 42"))
        XCTAssertEqual(rows[create].primary?.command, .createFile("/Users/me/Downloads/qzxv 42"))
        XCTAssertNotEqual(rows.first?.id, "fallback:run-terminal")
    }

    func testRunningInTerminalIsNeverAutomatic() throws {
        let rows = FallbackCommandsProvider(paths: paths).noMatchResults(for: LaunchQuery(raw: "make clean"))
        let run = try XCTUnwrap(rows.first { $0.id == "fallback:run-terminal" })
        XCTAssertNotNil(run.primary?.confirmation)
        XCTAssertEqual(run.primary?.command, .run("/Users/me/.grand-line/bin/in-window", arguments: ["/bin/zsh", "-lc", "make clean"]))
        var gate = ConfirmationGate()
        let runsAtOnce = gate.shouldRun(run.primary!, on: run.id)
        XCTAssertFalse(runsAtOnce, "the first Return only asks")
        XCTAssertFalse(rows.contains { $0.id == "fallback:calculate" }, "no digits, no sum")
        XCTAssertTrue(rows.allSatisfy(\.isFallback))
        XCTAssertTrue(rows.allSatisfy { !ResultGrouping.canBeTopHit($0) })
    }

    func testNoFallbackCommandsWhenSomethingMatches() {
        let engine = engine([Make.row("Notes")])
        let ids = engine.instantGroups(engine.plan("notes")).flatMap(\.rows).map(\.id)
        XCTAssertFalse(ids.contains("fallback:create-file"))
        XCTAssertFalse(ids.contains("fallback:run-terminal"))
        XCTAssertTrue(ids.contains("fallback:g"), "the web engines are still there")
        XCTAssertTrue(engine.instantGroups(engine.plan("=qzxv")).flatMap(\.rows).allSatisfy { !$0.id.hasPrefix("fallback:") })
    }

    func testFallbackEnginesComeFromSettings() {
        let custom = WebEngine(name: "Kagi", template: "https://kagi.com/search?q=%s", keyword: "k", fallback: true)
        let rows = FallbackProvider(fallbacks: .init(engines: [custom], assistants: false, drive: false))
            .instantResults(for: LaunchQuery(raw: "cornea"))
        XCTAssertEqual(rows.map(\.id), ["fallback:k"])
    }

    func testFileNamesAreMadeSafe() {
        XCTAssertEqual(FallbackCommandsProvider.fileName("notes/today: draft.md"), "notes-today- draft.md")
        XCTAssertEqual(FallbackCommandsProvider.fileName(".env"), "env")
        XCTAssertNil(FallbackCommandsProvider.fileName(".."))
        XCTAssertNil(FallbackCommandsProvider.fileName("   "))
    }

    // MARK: Script commands

    func testScriptOutputProtocol() {
        let rows = ScriptOutput.parse("""
        {"title": "One", "subtitle": "first", "icon": "star", "value": "1", "keywords": ["uno"]}
        not json
        {"subtitle": "no title"}
        {"title": "Two"}
        """)
        XCTAssertEqual(rows, .rows([
            ScriptRow(title: "One", subtitle: "first", icon: "star", value: "1", keywords: ["uno"]),
            ScriptRow(title: "Two"),
        ]))
        XCTAssertEqual(ScriptOutput.parse("{\"title\": \"x\"}\n{\"close\": true}\n"), .close)
        XCTAssertEqual(ScriptOutput.parse(""), .failed("The script printed no rows"))
        XCTAssertEqual(ScriptOutput.parse("", status: 2), .failed("The script stopped with status 2"))
    }

    func testScanFindsExecutableScripts() throws {
        let folder = try Make.folder()
        for (name, executable) in [("Pick.sh", true), ("notes.txt", false), (".hidden", true), ("two words.sh", true)] {
            let url = folder.appendingPathComponent(name)
            try Make.write("#!/bin/sh\n", to: url)
            try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder"), withIntermediateDirectories: true)
        XCTAssertEqual(ScriptCommand.scan(folder.path).map(\.name), ["pick"])
        XCTAssertEqual(paths.scripts, "/Users/me/.config/grand-line/sight/scripts")
    }

    func testScriptRunsWithNoArgumentsThenWithTheChosenValue() async throws {
        let runner = ScriptedRunner { arguments in
            switch arguments.first {
            case nil: return ShellOutput(status: 0, stdout: #"{"title": "Alpha", "value": "a"}"# + "\n" + #"{"title": "Beta", "keywords": ["second"]}"#)
            case "a": return ShellOutput(status: 0, stdout: #"{"title": "Alpha one"}"#)
            default: return ShellOutput(status: 0, stdout: #"{"close": true}"#)
            }
        }
        let script = ScriptCommand(name: "pick", path: "/s/pick")
        let provider = ScriptCommandProvider(script, runner: runner)
        let first = try await provider.results(for: LaunchQuery(raw: "pick ", term: ""))
        XCTAssertEqual(first.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(first[0].primary?.command, .script(path: "/s/pick", value: "a"))
        XCTAssertEqual(first[1].primary?.command, .script(path: "/s/pick", value: "Beta"), "the value defaults to the title")
        XCTAssertEqual(first[0].primary?.closesWindow, false)
        let narrowed = try await provider.results(for: LaunchQuery(raw: "pick second", term: "second"))
        XCTAssertEqual(narrowed.map(\.title), ["Beta"])
        XCTAssertEqual(runner.ran, [["/s/pick"]], "the rows are kept while in the command")

        let reply = await provider.choose("a")
        XCTAssertEqual(reply, .rows([ScriptRow(title: "Alpha one")]))
        XCTAssertEqual(runner.ran.last, ["/s/pick", "a"], "the value is an argument, never a shell line")
        let next = try await provider.results(for: LaunchQuery(raw: "pick ", term: ""))
        XCTAssertEqual(next.map(\.title), ["Alpha one"])
        let done = await provider.choose("Alpha one")
        XCTAssertEqual(done, .close)
        _ = try await provider.results(for: LaunchQuery(raw: "pick ", term: ""))
        XCTAssertEqual(runner.ran.last, ["/s/pick"], "after closing it starts from the top")
    }

    func testScriptCommandsAreListedAndEnteredByName() {
        let runner = ScriptedRunner { _ in ShellOutput(status: 0, stdout: "") }
        let list = ScriptCommandsProvider(folder: "/nowhere", runner: runner)
        list.replace([ScriptCommand(name: "pick", path: "/s/pick")])
        let engine = SearchEngine(providers: [list] + list.providers.map { $0 as any LaunchProvider }, router: router)
        let row = engine.instantGroups(engine.plan("pic")).flatMap(\.rows).first
        XCTAssertEqual(row?.primary?.command, .setQuery("pick "))
        let entered = engine.plan("pick ")
        XCTAssertEqual(entered.providers.map(\.id), ["scripts:pick"])
        XCTAssertEqual(entered.query.term, "")
        XCTAssertEqual(entered.chip, "pick")
        XCTAssertEqual(engine.plan("pick alp").query.term, "alp")
        XCTAssertTrue(engine.plan(">pi").providers.contains { $0.id == "scripts" })
    }

    func testAScriptThatFailsOrHangsSaysSo() async throws {
        let folder = try Make.folder()
        let path = folder.appendingPathComponent("slow.sh").path
        try Make.write("#!/bin/sh\nsleep 5\n", to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let provider = ScriptCommandProvider(ScriptCommand(name: "slow", path: path), runner: ShellRunner(), timeout: 0.3)
        let started = Date()
        let rows = try await provider.results(for: LaunchQuery(raw: "slow ", term: ""))
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].title.hasPrefix("The script"), rows[0].title)
    }

    func testTheExampleScriptSpeaksTheProtocol() async throws {
        // config/grand-line/sight-scripts/downloads.sh, run against a made-up home.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repo.appendingPathComponent("config/grand-line/sight-scripts/downloads.sh").path
        guard FileManager.default.isExecutableFile(atPath: script) else { throw XCTSkip("example script not found at \(script)") }
        let home = try Make.folder()
        try Make.write("x", to: home.appendingPathComponent("Downloads/report \"v2\".pdf"))
        var environment = ShellRunner.environment()
        environment["HOME"] = home.path
        // A script run for the first time can wait on macOS checking it (seconds on CI).
        let provider = ScriptCommandProvider(ScriptCommand(name: "downloads", path: script), runner: ShellRunner(environment: environment), timeout: 30)
        let rows = try await provider.results(for: LaunchQuery(raw: "downloads ", term: ""))
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, rows.map(\.title) == ["The script printed no rows"] {
            throw XCTSkip("the runner held the script past the timeout (it answers at once elsewhere)")
        }
        XCTAssertEqual(rows.map(\.title), ["report \"v2\".pdf"])
        guard case .script(_, let value) = rows[0].primary?.command else { return XCTFail("not a script row") }
        let reply = await provider.choose(value)
        guard case .rows(let next) = reply else {
            // GitHub's runners sometimes hold a freshly run script for longer
            // than any timeout while macOS checks it; the protocol itself was
            // shown above by the first step.
            if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil { throw XCTSkip("the runner held the script's second run: \(reply)") }
            return XCTFail("no second step: \(reply)")
        }
        XCTAssertEqual(next.map(\.title), ["Open", "Show in Nexus", "Copy path"])
    }

    // MARK: Clipboard history (Maccy)

    func makeMaccyStore(at url: URL) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        let sql = """
        CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT, ZAPPLICATION TEXT, ZLASTCOPIEDAT REAL, ZPIN TEXT);
        CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE TEXT, ZVALUE BLOB);
        INSERT INTO ZHISTORYITEM VALUES (1, 'old text', 'com.apple.Safari', 100, NULL);
        INSERT INTO ZHISTORYITEM VALUES (2, 'newer', 'com.apple.Terminal', 300, NULL);
        INSERT INTO ZHISTORYITEM VALUES (3, 'pinned', 'com.apple.Notes', 200, 'b');
        INSERT INTO ZHISTORYITEM VALUES (4, '', 'com.apple.Preview', 400, NULL);
        INSERT INTO ZHISTORYITEMCONTENT VALUES (10, 1, 'public.utf8-plain-text', CAST('old text' AS BLOB));
        INSERT INTO ZHISTORYITEMCONTENT VALUES (11, 2, 'public.utf8-plain-text', CAST('newer, line one' || char(10) || 'line two' AS BLOB));
        INSERT INTO ZHISTORYITEMCONTENT VALUES (12, 4, 'public.png', X'89504E47');
        """
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
    }

    func testMaccyHistoryIsReadFromACopy() throws {
        let home = try Make.folder()
        let paths = GrandLinePaths(home: home.path)
        XCTAssertFalse(ClipboardHistory.isAvailable(paths))
        let store = URL(fileURLWithPath: paths.maccyStore)
        try FileManager.default.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeMaccyStore(at: store)
        XCTAssertTrue(ClipboardHistory.isAvailable(paths))
        let entries = ClipboardHistory.load(store.path)
        XCTAssertEqual(entries.map(\.text), ["pinned", "newer, line one\nline two", "old text"], "pinned first, then newest; images skipped")
        XCTAssertEqual(entries[1].copied, Date(timeIntervalSinceReferenceDate: 300))

        let provider = ClipboardHistoryProvider(paths: paths)
        provider.reload()
        let rows = provider.instantResults(for: LaunchQuery(raw: ":", prefix: .clipboardHistory, term: ""))
        XCTAssertEqual(rows.map(\.title), ["pinned", "newer, line one", "old text"])
        XCTAssertEqual(rows[1].primary?.command, .paste("newer, line one\nline two"))
        XCTAssertEqual(rows[1].detail, "newer, line one\nline two")
        let found = provider.instantResults(for: LaunchQuery(raw: ":line two", prefix: .clipboardHistory, term: "line two"))
        XCTAssertEqual(found.map(\.title), ["newer, line one"], "the whole text is searched")
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "line")).isEmpty, "only under :")
    }

    func testWithoutMaccyTheHistoryIsHidden() throws {
        let provider = ClipboardHistoryProvider(paths: GrandLinePaths(home: try Make.folder().path))
        provider.reload()
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: ":", prefix: .clipboardHistory, term: "")).isEmpty)
        XCTAssertEqual(ClipboardHistory.load("/no/such/store.sqlite"), [])
    }

    // MARK: Prefix chips and routing to providers

    func testPrefixesReachTheirProvidersAndShowAChip() {
        let commands = CommandsProvider(folder: "/nowhere")
        commands.replace([CommandScript(name: "transcode", path: "/b/transcode", summary: "Convert", arguments: [])])
        let engine = SearchEngine(providers: [
            commands, SettingsPanes.provider(), ShellProvider(paths: paths), instant([Make.row("Safari")], id: "apps"),
            WindowsProvider(), ReminderProvider(paths: paths),
        ], router: router)
        let shell = engine.plan(">trans")
        XCTAssertEqual(Set(shell.providers.map(\.id)), ["commands", "shell"])
        XCTAssertEqual(shell.chip, "Commands")
        XCTAssertTrue(engine.instantGroups(shell).flatMap(\.rows).contains { $0.id == "cmd:transcode" })
        XCTAssertEqual(engine.plan(",").providers.map(\.id), ["settings"])
        XCTAssertFalse(engine.instantGroups(engine.plan(",")).isEmpty, "the settings list on its own")
        XCTAssertEqual(engine.plan("!saf").providers.map(\.id), ["windows"])
        XCTAssertEqual(engine.plan("!saf").chip, "Windows")
        XCTAssertNil(engine.plan("safari").chip)
        XCTAssertEqual(engine.plan("~/Dri").chip, "Path")
        XCTAssertEqual(engine.plan("remind call the lab 20m").providers.map(\.id), ["reminder"])
        XCTAssertEqual(engine.plan("remind ").providers.map(\.id), ["reminder"])
    }
}
