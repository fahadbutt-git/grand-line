import XCTest
import IndexKit
@testable import LauncherKit

/// On and off in every setting's own words, reads that finish out of order,
/// web engines changed during a reload, programs that print or run without
/// end, Maccy's store read only when it changed, and stale menu reads.
final class ReviewFixTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")

    func first(_ text: String) -> SettingsActions.Request? {
        SettingsActions.parse(text).first?.request
    }

    // MARK: On and off mean what the words say

    /// Each setting's phrasings, alone and with on and off: the state of the
    /// setting itself (Mute microphone, Dock autohide) that each one asks for.
    func testEverySettingsOnAndOffPhrasing() {
        let cases: [(String, String, Bool?)] = [
            ("dark mode", "darkmode", nil), ("dark mode on", "darkmode", true), ("dark mode off", "darkmode", false),
            ("light mode", "darkmode", false), ("light mode on", "darkmode", false), ("light mode off", "darkmode", true),
            ("wifi", "wifi", nil), ("wifi on", "wifi", true), ("wifi off", "wifi", false),
            ("bluetooth on", "bluetooth", true), ("bluetooth off", "bluetooth", false),
            ("dnd on", "dnd", true), ("do not disturb off", "dnd", false),
            ("mute", "mute", nil), ("mute on", "mute", true), ("mute off", "mute", false),
            ("unmute", "mute", false), ("sound mute on", "mute", true),
            // The microphone by itself: on is the microphone working.
            ("mic", "micmute", nil), ("mic on", "micmute", false), ("mic off", "micmute", true),
            ("microphone on", "micmute", false), ("turn the microphone off", "micmute", true),
            ("mute mic on", "micmute", true), ("mute microphone off", "micmute", false),
            ("unmute mic", "micmute", false), ("mic muted on", "micmute", true),
            ("hidden files on", "hiddenfiles", true), ("hidden files off", "hiddenfiles", false),
            ("show hidden files", "hiddenfiles", true), ("hide hidden files", "hiddenfiles", false),
            // The Dock by itself: on is the Dock always shown, so autohide off.
            ("dock", "dockautohide", nil), ("dock on", "dockautohide", false), ("dock off", "dockautohide", true),
            ("dock autohide on", "dockautohide", true), ("dock autohide off", "dockautohide", false),
            ("hide dock", "dockautohide", true), ("show dock", "dockautohide", false), ("dock always shown", "dockautohide", false),
            ("desktop icons on", "desktopicons", true), ("desktop icons off", "desktopicons", false),
            ("hide desktop icons", "desktopicons", false),
            // The menu bar by itself: on is the menu bar shown.
            ("menu bar", "menubarautohide", nil), ("menu bar on", "menubarautohide", false), ("menu bar off", "menubarautohide", true),
            ("menubar on", "menubarautohide", false), ("turn the menu bar on", "menubarautohide", false),
            ("menu bar autohide on", "menubarautohide", true), ("autohide menu bar off", "menubarautohide", false),
            ("hide menu bar", "menubarautohide", true), ("show menu bar", "menubarautohide", false),
            ("keep awake on", "keepawake", true), ("keep awake off", "keepawake", false), ("caffeinate", "keepawake", nil),
        ]
        for (text, key, desired) in cases {
            XCTAssertEqual(first(text), .toggle(key: key, desired: desired), text)
        }
        // Every toggle is covered above.
        XCTAssertEqual(Set(cases.map(\.1)), Set(SettingsActions.toggles.map(\.key)))
    }

    func testMicrophoneOnUnmutesThroughTheCommand() throws {
        let state = SettingsState(values: ["mic-muted": true])
        let match = try XCTUnwrap(SettingsActions.parse("microphone on").first)
        let row = try XCTUnwrap(SettingsActionsProvider.row(match, state: state, phases: [:], paths: paths))
        // bin/toggle's mic setting is "muted": off unmutes.
        XCTAssertEqual(row.primary?.command, .run(paths.command("toggle"), arguments: ["mic", "off"]))
        let dock = try XCTUnwrap(SettingsActions.parse("dock on").first)
        let dockRow = try XCTUnwrap(SettingsActionsProvider.row(dock, state: SettingsState(values: ["dock": false]), phases: [:], paths: paths))
        // bin/toggle's dock on is the Dock always shown.
        XCTAssertEqual(dockRow.primary?.command, .run(paths.command("toggle"), arguments: ["dock", "on"]))
    }

    // MARK: Reads that finish out of order

    func testAnOlderReadNeverReplacesANewerValue() {
        var stamps: [String: Int] = [:]
        var state = SettingsState().merging(SettingsState(values: ["wifi": false]), started: 2, stamps: &stamps)
        state = state.merging(SettingsState(values: ["wifi": true, "dark": true], volume: 30), started: 1, stamps: &stamps)
        XCTAssertEqual(state.values["wifi"], false, "read 2 started after read 1: its value stays")
        XCTAssertEqual(state.values["dark"], true, "values read 2 did not read are taken")
        XCTAssertEqual(state.volume, 30)
        state = state.merging(SettingsState(values: ["wifi": true]), started: 3, stamps: &stamps)
        XCTAssertEqual(state.values["wifi"], true)
    }

    func testAFullReadThatEndsAfterAChangeKeepsTheChange() async throws {
        let mac = SlowStatusMac()
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        // The window opens: the full read starts and takes a while.
        let full = Task { await provider.readState() }
        try await Task.sleep(nanoseconds: 50_000_000)
        // Meanwhile "wifi off": the change and its own read back.
        mac.set("wifi", false)
        await provider.readState(["wifi"])
        XCTAssertEqual(provider.currentState?.values["wifi"], false)
        await full.value
        XCTAssertEqual(provider.currentState?.values["wifi"], false, "the full read began before the change")
        XCTAssertEqual(provider.currentState?.values["dark"], false)
    }

    // MARK: Web engines changed during a reload

    func testEnginesChangedDuringAReloadAreKept() {
        let provider = WebProvider(quicklinksFile: "/nonexistent/quicklinks.tsv")
        let chosen = Array(WebEngineList.standard.prefix(1))
        var changed = false
        provider.afterBuild = {
            guard !changed else { return }
            changed = true
            provider.setEngines(chosen)
        }
        provider.reload()
        provider.afterBuild = nil
        let expected = WebEngineList.searches(chosen, quicklinks: "").map(\.keyword)
        XCTAssertEqual(provider.current.map(\.keyword), expected)
    }

    // MARK: Programs that print or run without end

    func testOutputIsCappedAndTheProgramStopped() async throws {
        let started = Date()
        let out = try await ShellRunner().run("/bin/sh", ["-c", "yes 'a line of output'"], timeout: 20)
        XCTAssertTrue(out.truncated)
        XCTAssertLessThanOrEqual(out.stdout.utf8.count, ShellRunner.maxOutput)
        XCTAssertGreaterThan(out.stdout.utf8.count, ShellRunner.maxOutput / 2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "stopped at the cap, not at the time limit")
        let small = try await ShellRunner().run("/bin/echo", ["hello"])
        XCTAssertFalse(small.truncated)
    }

    func testAProgramThatIgnoresSIGTERMIsKilled() async throws {
        let started = Date()
        let out = try await ShellRunner().run("/bin/sh", ["-c", "trap '' TERM; sleep 30"], timeout: 0.3)
        XCTAssertEqual(out.status, ShellRunner.stoppedStatus)
        XCTAssertLessThan(Date().timeIntervalSince(started), ShellRunner.killAfter + 4)
    }

    func testAStopReachesWhatTheProgramStarted() async throws {
        let folder = try Make.folder()
        let pidFile = folder.appendingPathComponent("child.pid").path
        _ = try await ShellRunner().run("/bin/sh", ["-c", "sleep 30 & echo $! > '\(pidFile)'; wait"], timeout: 0.5)
        let child = try XCTUnwrap(Int32(String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        var gone = false
        for _ in 0..<50 where !gone {
            gone = kill(child, 0) != 0
            if !gone { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        XCTAssertTrue(gone, "the child in the program's group was stopped too")
    }

    func testAProgramThatCannotStartThrows() async {
        do {
            _ = try await ShellRunner().run("/nonexistent/program", [], timeout: 1)
            XCTFail("it started")
        } catch {}
    }

    func testScriptAndProviderRowsAreCapped() {
        let lines = (0..<(ScriptOutput.maxRows + 50)).map { #"{"title": "row \#($0)"}"# }.joined(separator: "\n")
        guard case .rows(let rows) = ScriptOutput.parse(lines) else { return XCTFail("no rows") }
        XCTAssertEqual(rows.count, ScriptOutput.maxRows)
        XCTAssertEqual(JSONLines.parse(lines, providerID: "ext:x", paths: paths).count, JSONLines.maxRows)
    }

    // MARK: Maccy's store

    func testMaccysStoreIsReadOnlyWhenItChanged() throws {
        let home = try Make.folder()
        let paths = GrandLinePaths(home: home.path)
        let store = URL(fileURLWithPath: ClipboardHistory.stores(paths)[1])
        try Make.write("first", to: store)
        let loads = Counter()
        let provider = ClipboardHistoryProvider(paths: paths) { _ in
            loads.add()
            return [ClipEntry(id: 1, text: "copied text")]
        }
        provider.reload()
        provider.reload()
        XCTAssertEqual(loads.value, 1, "the same store is not copied again")
        XCTAssertEqual(provider.instantResults(for: LaunchQuery(raw: ":", prefix: .clipboardHistory, term: "")).map(\.title), ["copied text"])
        try Make.write("second, longer", to: store)
        provider.reload()
        XCTAssertEqual(loads.value, 2)
        try Make.write("wal", to: URL(fileURLWithPath: store.path + "-wal"))
        provider.reload()
        XCTAssertEqual(loads.value, 3, "a new write-ahead log is a change too")
        try FileManager.default.removeItem(at: store)
        provider.reload()
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: ":", prefix: .clipboardHistory, term: "")).isEmpty)
    }

    // MARK: Only the newest read

    func testOnlyTheNewestReadIsApplied() {
        let reads = LatestOnly()
        let a = reads.next()
        let b = reads.next()
        var applied: [Int] = []
        let stale = reads.ifCurrent(a) { applied.append(a) }
        let fresh = reads.ifCurrent(b) { applied.append(b) }
        XCTAssertFalse(stale)
        XCTAssertTrue(fresh)
        XCTAssertEqual(applied, [b])
        XCTAssertFalse(reads.isCurrent(a))
    }
}

/// `toggle status` that takes a while for a full read and answers at once
/// for named settings, with values set from the test.
final class SlowStatusMac: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Bool] = ["wifi": true, "dark": false]

    func set(_ key: String, _ value: Bool) {
        lock.withLock { values[key] = value }
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ShellOutput {
        let names = Array(arguments.dropFirst())
        // The full read sees the state from when it started.
        let snapshot = lock.withLock { values }
        if names.isEmpty { try await Task.sleep(nanoseconds: 300_000_000) }
        let lines = snapshot.keys.sorted().filter { names.isEmpty || names.contains($0) }.map { "\($0) \(snapshot[$0]! ? "on" : "off")" }
        return ShellOutput(status: 0, stdout: lines.joined(separator: "\n") + "\n")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
