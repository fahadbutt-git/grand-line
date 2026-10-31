import XCTest
@testable import LauncherKit

/// A pretend Mac behind bin/toggle and bin/power: `toggle status` prints its
/// state, and changes change it, unless told to fail or to ignore them.
final class FakeMac: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Bool]
    private var volume: Int
    private(set) var calls: [[String]] = []
    var failure: (status: Int32, output: String)?
    var ignoresChanges = false

    init(values: [String: Bool] = ["dark": false, "wifi": true, "bluetooth": true, "dock": true, "mute": false, "hidden": false, "menubar": true],
         volume: Int = 40) {
        self.values = values
        self.volume = volume
    }

    func value(_ key: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    var changes: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return calls.filter { $0.dropFirst().first != "status" }
    }

    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ShellOutput {
        lock.lock(); defer { lock.unlock() }
        let command = (executable as NSString).lastPathComponent
        calls.append([command] + arguments)
        if command == "toggle", arguments.first == "status" {
            let names = arguments.dropFirst()
            var lines: [String] = []
            for key in values.keys.sorted() where names.isEmpty || names.contains(key) {
                lines.append("\(key) \(values[key]! ? "on" : "off")")
            }
            if names.isEmpty || names.contains("volume") { lines.append("volume \(volume)") }
            return ShellOutput(status: 0, stdout: lines.joined(separator: "\n") + "\n")
        }
        if let failure { return ShellOutput(status: failure.status, stdout: failure.output) }
        guard command == "toggle", !ignoresChanges, let name = arguments.first else { return ShellOutput(status: 0, stdout: "") }
        if name == "volume" {
            switch arguments[1] {
            case "up": volume = min(100, volume + 10)
            case "down": volume = max(0, volume - 10)
            default: volume = Int(arguments[1]) ?? volume
            }
        } else {
            values[name] = arguments.count == 2 ? arguments[1] == "on" : !(values[name] ?? false)
        }
        return ShellOutput(status: 0, stdout: "")
    }
}

final class SettingsActionsTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")
    var toggle: String { paths.command("toggle") }

    func requests(_ text: String) -> [SettingsActions.Request] {
        SettingsActions.parse(text).map(\.request)
    }

    // MARK: Phrasings

    func testPhrasingsBecomeRequests() {
        XCTAssertEqual(requests("dark").first, .toggle(key: "darkmode", desired: nil))
        XCTAssertEqual(requests("dark mode on").first, .toggle(key: "darkmode", desired: true))
        XCTAssertEqual(requests("Turn off dark mode").first, .toggle(key: "darkmode", desired: false))
        XCTAssertEqual(requests("light mode").first, .toggle(key: "darkmode", desired: false))
        XCTAssertEqual(requests("light mode off").first, .toggle(key: "darkmode", desired: true))
        XCTAssertEqual(requests("wifi").first, .toggle(key: "wifi", desired: nil))
        XCTAssertEqual(requests("Wi-Fi").first, .toggle(key: "wifi", desired: nil))
        XCTAssertEqual(requests("turn off wifi").first, .toggle(key: "wifi", desired: false))
        XCTAssertEqual(requests("turn wifi on").first, .toggle(key: "wifi", desired: true))
        XCTAssertEqual(requests("bt off").first, .toggle(key: "bluetooth", desired: false))
        XCTAssertEqual(requests("enable bluetooth").first, .toggle(key: "bluetooth", desired: true))
        XCTAssertEqual(requests("do not disturb").first, .toggle(key: "dnd", desired: nil))
        XCTAssertEqual(requests("dnd on").first, .toggle(key: "dnd", desired: true))
        XCTAssertEqual(requests("focus off").first, .toggle(key: "dnd", desired: false))
        XCTAssertEqual(requests("mute").first, .toggle(key: "mute", desired: nil))
        XCTAssertEqual(requests("unmute").first, .toggle(key: "mute", desired: false))
        XCTAssertEqual(requests("mute mic").first, .toggle(key: "micmute", desired: nil))
        XCTAssertEqual(requests("hidden files").first, .toggle(key: "hiddenfiles", desired: nil))
        XCTAssertEqual(requests("show hidden files").first, .toggle(key: "hiddenfiles", desired: true))
        XCTAssertEqual(requests("hide hidden files").first, .toggle(key: "hiddenfiles", desired: false))
        XCTAssertEqual(requests("hide dock").first, .toggle(key: "dockautohide", desired: true))
        XCTAssertEqual(requests("dock autohide off").first, .toggle(key: "dockautohide", desired: false))
        XCTAssertEqual(requests("auto-hide menu bar").first, .toggle(key: "menubarautohide", desired: nil))
        XCTAssertEqual(requests("desktop icons off").first, .toggle(key: "desktopicons", desired: false))
        XCTAssertEqual(requests("caffeinate").first, .toggle(key: "keepawake", desired: nil))
        XCTAssertEqual(requests("keep the mac awake").first, .toggle(key: "keepawake", desired: nil))
    }

    func testVolumePhrasings() {
        XCTAssertEqual(requests("volume 30"), [.volumeSet(30)])
        XCTAssertEqual(requests("volume 30%"), [.volumeSet(30)])
        XCTAssertEqual(requests("set volume to 30"), [.volumeSet(30)])
        XCTAssertEqual(requests("vol 150"), [.volumeSet(100)])
        XCTAssertEqual(requests("volume max"), [.volumeSet(100)])
        XCTAssertEqual(requests("volume up"), [.volumeUp])
        XCTAssertEqual(requests("louder"), [.volumeUp])
        XCTAssertEqual(requests("volume down"), [.volumeDown])
        XCTAssertEqual(requests("volume off"), [.toggle(key: "mute", desired: true)])
        XCTAssertEqual(requests("volume"), [.volumeUp, .volumeDown, .toggle(key: "mute", desired: nil)])
        XCTAssertEqual(requests("volume 1234"), [])
    }

    func testActionPhrasings() {
        XCTAssertEqual(requests("lock").first, .action(key: "lock"))
        XCTAssertEqual(requests("lock screen").first, .action(key: "lock"))
        XCTAssertEqual(requests("display off").first, .action(key: "displaysleep"))
        XCTAssertEqual(requests("sleep").first, .action(key: "sleep"))
        XCTAssertEqual(requests("reboot").first, .action(key: "restart"))
        XCTAssertEqual(requests("shut down").first, .action(key: "shutdown"))
        XCTAssertEqual(requests("screenshot").first, .action(key: "screenshot.area"))
        XCTAssertTrue(requests("screenshot").contains(.action(key: "screenshot.window")))
        XCTAssertEqual(requests("night shift").first, .action(key: "nightshift"))
        XCTAssertEqual(requests("low power mode").first, .action(key: "lowpower"))
    }

    func testHalfTypedAndUnrelatedText() {
        XCTAssertEqual(requests("wifi o").first, .toggle(key: "wifi", desired: nil))
        XCTAssertEqual(SettingsActions.parse("wifi o").first?.exact, true)
        XCTAssertEqual(requests("blu").first, .toggle(key: "bluetooth", desired: nil))
        XCTAssertEqual(SettingsActions.parse("blu").first?.exact, false)
        XCTAssertEqual(requests("wi"), [])
        XCTAssertEqual(requests("wifi on off"), [])
        XCTAssertEqual(requests("glaucoma review"), [])
        XCTAssertEqual(requests(""), [])
    }

    func testNoEmptyTrashOrOtherDeletion() {
        XCTAssertEqual(requests("empty trash"), [])
        let commands = (SettingsActions.toggles + SettingsActions.actions).map(\.key)
        XCTAssertFalse(commands.contains { $0.contains("trash") })
    }

    // MARK: Rows

    func rows(_ text: String, state: SettingsState?, phases: [String: SettingPhase] = [:]) -> [LaunchResult] {
        SettingsActions.parse(text).compactMap { SettingsActionsProvider.row($0, state: state, phases: phases, paths: paths) }
    }

    func testRowShowsStateAndOffersTheOtherOne() throws {
        let row = try XCTUnwrap(rows("dark mode", state: SettingsState(values: ["dark": true])).first)
        XCTAssertEqual(row.id, "setting.darkmode")
        XCTAssertEqual(row.title, "Dark mode: On")
        XCTAssertEqual(row.subtitle, "Return turns it off")
        XCTAssertEqual(row.accessory, "On")
        XCTAssertEqual(row.primary?.command, .run(toggle, arguments: ["dark", "off"]))
        XCTAssertEqual(row.primary?.closesWindow, false)
        guard case .openURL(let url, _)? = row.secondary?.command else { return XCTFail("no pane on Command+Return") }
        XCTAssertTrue(url.hasSuffix("com.apple.Appearance-Settings.extension"))
    }

    func testRowBeforeTheStateIsReadFlips() throws {
        let row = try XCTUnwrap(rows("wifi", state: nil).first)
        XCTAssertEqual(row.title, "Wi-Fi")
        XCTAssertEqual(row.subtitle, "Checking…")
        XCTAssertEqual(row.primary?.command, .run(toggle, arguments: ["wifi"]))
        let typed = try XCTUnwrap(rows("wifi off", state: nil).first)
        XCTAssertEqual(typed.primary?.command, .run(toggle, arguments: ["wifi", "off"]))
    }

    func testAskingForTheCurrentStateOffersTheOtherOne() throws {
        let row = try XCTUnwrap(rows("wifi off", state: SettingsState(values: ["wifi": false])).first)
        XCTAssertEqual(row.title, "Wi-Fi: Off")
        XCTAssertEqual(row.primary?.command, .run(toggle, arguments: ["wifi", "on"]))
    }

    func testInvertedSettingsReadAsPeopleSayThem() throws {
        // The Dock always shown is autohide off.
        let row = try XCTUnwrap(rows("hide dock", state: SettingsState(values: ["dock": true])).first)
        XCTAssertEqual(row.title, "Dock autohide: Off")
        XCTAssertEqual(row.primary?.command, .run(toggle, arguments: ["dock", "off"]))
        let menu = try XCTUnwrap(rows("show menu bar", state: SettingsState(values: ["menubar": false])).first)
        XCTAssertEqual(menu.title, "Menu bar autohide: On")
        XCTAssertEqual(menu.primary?.command, .run(toggle, arguments: ["menubar", "on"]))
    }

    func testVolumeRows() throws {
        let set = try XCTUnwrap(rows("volume 30", state: SettingsState(volume: 55)).first)
        XCTAssertEqual(set.id, "setting.volume")
        XCTAssertEqual(set.title, "Set volume to 30%")
        XCTAssertEqual(set.subtitle, "Now 55%, Return makes it 30%")
        XCTAssertEqual(set.primary?.command, .run(toggle, arguments: ["volume", "30"]))
        let up = try XCTUnwrap(rows("volume up", state: SettingsState(volume: 95)).first)
        XCTAssertEqual(up.subtitle, "Now 95%, Return makes it 100%")
        XCTAssertEqual(rows("volume", state: SettingsState()).map(\.id), ["setting.volume.up", "setting.volume.down", "setting.mute"])
    }

    func testPowerActionsAskFirstAndCloseTheWindow() throws {
        for (text, arg) in [("restart", "restart"), ("shut down", "shutdown"), ("sleep", "sleep"), ("log out", "logout")] {
            let row = try XCTUnwrap(rows(text, state: nil).first, text)
            XCTAssertNotNil(row.primary?.confirmation, text)
            XCTAssertEqual(row.primary?.closesWindow, true)
            XCTAssertEqual(row.primary?.command, .run(paths.command("power"), arguments: [arg]))
        }
        let lock = try XCTUnwrap(rows("lock", state: nil).first)
        XCTAssertNil(lock.primary?.confirmation)
        XCTAssertEqual(lock.id, "setting.lock")
    }

    func testPaneOnlySettingsSayWhy() throws {
        let night = try XCTUnwrap(rows("night shift", state: nil).first)
        XCTAssertTrue(night.subtitle.contains("no command"))
        guard case .openURL(let url, _)? = night.primary?.command else { return XCTFail("night shift opens a pane") }
        XCTAssertTrue(url.contains("Displays"))
        let low = try XCTUnwrap(rows("low power", state: nil).first)
        XCTAssertTrue(low.subtitle.contains("administrator password"))
        XCTAssertEqual(low.actions.count, 1)
    }

    func testWorkingAndFailedRows() throws {
        let working = try XCTUnwrap(rows("wifi", state: SettingsState(values: ["wifi": true]), phases: ["setting.wifi": .running("Turning off…")]).first)
        XCTAssertEqual(working.title, "Wi-Fi: Turning off…")
        XCTAssertEqual(working.accessory, "Working")
        let failure = SettingFailure("Allow Automation for System Events in Privacy & Security", permission: .automation)
        let failed = try XCTUnwrap(rows("dark", state: SettingsState(values: ["dark": false]), phases: ["setting.darkmode": .failed(failure)]).first)
        XCTAssertEqual(failed.title, "Dark mode: not changed")
        XCTAssertEqual(failed.subtitle, failure.message)
        XCTAssertEqual(failed.primary?.command, .openURL(SettingsActions.Permission.automation.paneURL, bundleID: nil))
        XCTAssertEqual(failed.secondary?.title, "Try again")
        XCTAssertEqual(failed.secondary?.command, .run(toggle, arguments: ["dark", "on"]))
    }

    func testStatusParsing() {
        let state = SettingsState.parse("dark on\nwifi off\nvolume 40\nnoise\nbluetooth maybe\n")
        XCTAssertEqual(state.values, ["dark": true, "wifi": false])
        XCTAssertEqual(state.volume, 40)
        let merged = state.merging(SettingsState(values: ["wifi": true]))
        XCTAssertEqual(merged.values["wifi"], true)
        XCTAssertEqual(merged.values["dark"], true)
        XCTAssertEqual(merged.volume, 40)
    }

    // MARK: Running, reading back

    func row(_ provider: SettingsActionsProvider, _ text: String) throws -> LaunchResult {
        try XCTUnwrap(provider.instantResults(for: LaunchQuery(raw: text)).first)
    }

    func testStateIsReadLiveAndForgottenWhenTheWindowOpens() async throws {
        let mac = FakeMac()
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        XCTAssertTrue(provider.claimRead())
        XCTAssertFalse(provider.claimRead(), "one read at a time")
        await provider.readState()
        XCTAssertEqual(try row(provider, "wifi").title, "Wi-Fi: On")
        XCTAssertEqual(mac.calls.first, ["toggle", "status"])
        provider.panelOpened()
        XCTAssertNil(provider.currentState)
        XCTAssertEqual(try row(provider, "wifi").subtitle, "Checking…")
        XCTAssertTrue(provider.claimRead())
    }

    func testReturnReturnReturnFlipsEachTime() async throws {
        let mac = FakeMac()
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        await provider.readState()
        for expected in [false, true, false] {
            let current = try row(provider, "wifi")
            guard case .started(let job) = provider.begin(current.primary!, resultID: current.id) else { return XCTFail("did not start") }
            await provider.finish(job)
            XCTAssertEqual(mac.value("wifi"), expected)
            XCTAssertEqual(try row(provider, "wifi").title, "Wi-Fi: \(expected ? "On" : "Off")")
            XCTAssertNil(provider.phase(of: "setting.wifi"))
        }
        XCTAssertEqual(mac.changes, [["toggle", "wifi", "off"], ["toggle", "wifi", "on"], ["toggle", "wifi", "off"]])
        // Each change is read back by name.
        XCTAssertEqual(mac.calls.filter { $0 == ["toggle", "status", "wifi"] }.count, 3)
    }

    func testRepeatedReturnWhileRunningIsIgnored() async throws {
        let mac = FakeMac()
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        await provider.readState()
        let current = try row(provider, "bt off")
        guard case .started(let job) = provider.begin(current.primary!, resultID: current.id) else { return XCTFail("did not start") }
        XCTAssertEqual(provider.begin(current.primary!, resultID: current.id), .busy)
        XCTAssertEqual(try row(provider, "bt off").title, "Bluetooth: Turning off…")
        await provider.finish(job)
        XCTAssertEqual(mac.changes, [["toggle", "bluetooth", "off"]])
        XCTAssertEqual(try row(provider, "bt off").title, "Bluetooth: Off")
    }

    func testAMissingPermissionIsShownWithItsPane() async throws {
        let mac = FakeMac()
        mac.failure = (3, "Allow Automation for System Events in Privacy & Security\n")
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        await provider.readState()
        let current = try row(provider, "dark mode on")
        guard case .started(let job) = provider.begin(current.primary!, resultID: current.id) else { return XCTFail("did not start") }
        let failure = await provider.finish(job)
        XCTAssertEqual(failure?.permission, .automation)
        let after = try row(provider, "dark mode on")
        XCTAssertEqual(after.title, "Dark mode: not changed")
        XCTAssertEqual(after.primary?.title, "Open Automation settings")
        provider.panelOpened()
        XCTAssertNil(provider.phase(of: "setting.darkmode"), "a new opening starts clean")
    }

    func testAChangeThatDidNotTakeIsAFailure() async throws {
        let mac = FakeMac()
        mac.ignoresChanges = true
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        await provider.readState()
        let current = try row(provider, "dark")
        guard case .started(let job) = provider.begin(current.primary!, resultID: current.id) else { return XCTFail("did not start") }
        let failure = await provider.finish(job)
        XCTAssertEqual(failure?.message, "macOS did not make the change")
        XCTAssertEqual(failure?.permission, .automation)
        XCTAssertEqual(try row(provider, "dark").title, "Dark mode: not changed")
    }

    func testVolumeIsReadBack() async throws {
        let mac = FakeMac(volume: 40)
        let provider = SettingsActionsProvider(paths: paths, runner: mac)
        await provider.readState()
        for _ in 0..<2 {
            let up = try row(provider, "volume up")
            guard case .started(let job) = provider.begin(up.primary!, resultID: up.id) else { return XCTFail("did not start") }
            await provider.finish(job)
        }
        XCTAssertEqual(provider.currentState?.volume, 60)
        XCTAssertEqual(try row(provider, "volume up").subtitle, "Now 60%, Return makes it 70%")
    }

    func testTimeoutsAndOtherFailures() {
        let job = SettingJob(resultID: "setting.restart", executable: "/p", arguments: ["restart"], timeout: 1, readBack: [], expectedKey: nil,
                             expectedValue: nil, expectedVolume: nil, permission: nil, toleratesTimeout: true)
        XCTAssertNil(SettingsActionsProvider.failure(status: 15, output: "", job: job))
        let wifi = SettingJob(resultID: "setting.wifi", executable: "/p", arguments: ["wifi"], timeout: 1, readBack: [], expectedKey: nil,
                              expectedValue: nil, expectedVolume: nil, permission: nil, toleratesTimeout: false)
        XCTAssertEqual(SettingsActionsProvider.failure(status: 15, output: "", job: wifi)?.message, "It took too long and was stopped")
        XCTAssertEqual(SettingsActionsProvider.failure(status: 5, output: "", job: wifi)?.permission, .accessibility)
        XCTAssertEqual(SettingsActionsProvider.failure(status: 4, output: "Bluetooth needs blueutil. Run: update\n", job: wifi)?.message,
                       "Bluetooth needs blueutil. Run: update")
    }

    func testAutomationThatNeverAnswersOrIsRefusedSaysWhichPermission() {
        // CI and a first run: osascript waits on the Automation question, or
        // macOS refuses with -1743. The row must say so, not keep working.
        let dark = SettingJob(resultID: "setting.darkmode", executable: "/p", arguments: ["dark", "on"], timeout: 30, readBack: ["dark"],
                              expectedKey: "dark", expectedValue: true, expectedVolume: nil, permission: .automation, toleratesTimeout: false)
        let stalled = SettingsActionsProvider.failure(status: 15, output: "", job: dark)
        XCTAssertEqual(stalled?.permission, .automation)
        XCTAssertEqual(stalled?.message, "System Events did not answer. Allow Automation for System Events in Privacy & Security")
        let refused = SettingsActionsProvider.failure(
            status: 1, output: "execution error: Not authorized to send Apple events to System Events. (-1743)\n", job: dark)
        XCTAssertEqual(refused, SettingFailure("Allow Automation for System Events in Privacy & Security", permission: .automation))
        XCTAssertEqual(SettingsActionsProvider.failure(status: 3, output: "", job: dark)?.permission, .automation)
    }

    func testScreenshotsAndPanesAreRunByTheWindow() throws {
        let provider = SettingsActionsProvider(paths: paths, runner: FakeMac())
        let shot = try row(provider, "screenshot")
        XCTAssertEqual(provider.begin(shot.primary!, resultID: shot.id), .notManaged)
        XCTAssertEqual(shot.primary?.command, .run(paths.command("capture"), arguments: ["area"]))
        let night = try row(provider, "night shift")
        XCTAssertEqual(provider.begin(night.primary!, resultID: night.id), .notManaged)
    }

    // MARK: Ranking and the list

    func testSettingsActionIsTheTopHitOverItsPane() async throws {
        let provider = SettingsActionsProvider(paths: paths, runner: FakeMac())
        await provider.readState()
        let menuRow = Make.row("Wi-Fi", id: "menu:Toggle/Wi-Fi", section: .grandLine)
        let engine = SearchEngine(providers: [SettingsPanes.provider(), instant([menuRow], id: "menu"), provider],
                                  router: PrefixRouter(pathExists: { _ in false }))
        for (text, id) in [("wifi", "setting.wifi"), ("dark mode", "setting.darkmode"), ("dark", "setting.darkmode"),
                           ("bluetooth", "setting.bluetooth"), ("do not disturb", "setting.dnd"), ("turn off wifi", "setting.wifi"),
                           ("mute", "setting.mute"), ("volume 30", "setting.volume"), ("hidden files", "setting.hiddenfiles"),
                           ("bt off", "setting.bluetooth"), ("lock screen", "setting.lock")] {
            let groups = engine.instantGroups(engine.plan(text))
            XCTAssertEqual(groups.first?.section, .topHit, text)
            XCTAssertEqual(groups.first?.rows.first?.id, id, text)
        }
    }

    func testUpdatingARowKeepsItsPlaceAndTheSelection() {
        var list = ResultList(groups: ResultGrouping.group([Make.row("A"), Make.row("B", id: "setting.wifi", section: .system)]), topHit: true)
        list.moveSelection(by: 1)
        var fresh = Make.row("Wi-Fi: Off", id: "setting.wifi", section: .system)
        fresh.accessory = "Off"
        list.update([fresh, Make.row("Not shown", id: "setting.dnd")])
        XCTAssertEqual(list.rows.map(\.title), ["A", "Wi-Fi: Off"])
        XCTAssertEqual(list.selected?.id, "setting.wifi")
        XCTAssertEqual(list.selected?.accessory, "Off")
    }

    func testEveryRowIDIsStable() {
        let ids = Set((SettingsActions.toggles + SettingsActions.actions).map(\.id))
        XCTAssertEqual(ids.count, SettingsActions.toggles.count + SettingsActions.actions.count)
        XCTAssertTrue(ids.contains("setting.darkmode"))
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("setting.") && !$0.contains(" ") })
    }
}
