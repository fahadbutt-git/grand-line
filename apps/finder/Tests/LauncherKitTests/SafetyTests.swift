import XCTest
import IndexKit
@testable import LauncherKit

/// What must never happen without asking, and what must never be written down:
/// irreversible rows ask first wherever they show, learning never lifts them,
/// clipboard text and pids never reach usage.json.
final class SafetyTests: XCTestCase {
    let router = PrefixRouter(pathExists: { _ in false }, clipboardHistory: { true })
    let paths = GrandLinePaths(home: "/Users/me")

    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func menuRow(_ line: String) throws -> LaunchResult {
        try XCTUnwrap(MenuProvider.results(MenuFile.parse([line]), states: nil).first)
    }

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
    }

    // MARK: Irreversible commands

    func testTheAppsOwnCommandsAreUsedOnlyWhenSetupHasNotRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("paths-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let home = root + "/home", bundled = root + "/Sight.app/Contents/Resources/grand-line"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: bundled + "/bin", withIntermediateDirectories: true)
        // Only the apps installed: the app's own copy.
        let alone = GrandLinePaths(home: home, bundled: bundled)
        XCTAssertEqual(alone.command("power"), bundled + "/bin/power")
        XCTAssertTrue(alone.isBundledPackage)
        XCTAssertEqual(ShellRunner.environment(paths: alone, base: [:])["GRAND_LINE_LINK"], bundled)
        // After setup: ~/.grand-line, whatever the app carries.
        try FileManager.default.createDirectory(atPath: home + "/.grand-line", withIntermediateDirectories: true)
        let setUp = GrandLinePaths(home: home, bundled: bundled)
        XCTAssertEqual(setUp.command("power"), home + "/.grand-line/bin/power")
        XCTAssertFalse(setUp.isBundledPackage)
        XCTAssertNil(ShellRunner.environment(paths: setUp, base: [:])["GRAND_LINE_LINK"])
    }

    func testIrreversibleCommandsAreRecognised() {
        for line in ["power restart", "power shutdown", "power logout", "power sleep", "$HOME/.grand-line/bin/power restart",
                     "exec power shutdown", "GRAND_LINE_QUIET=1 power sleep", "/sbin/shutdown -h now", "pmset sleepnow"] {
            XCTAssertTrue(UsagePolicy.isIrreversible(.shell(line)), line)
        }
        for line in ["power lock", "power display-sleep", "toggle dark", "capture area", "open 'x-apple.systempreferences:'", "pmset -g"] {
            XCTAssertFalse(UsagePolicy.isIrreversible(.shell(line)), line)
        }
        XCTAssertTrue(UsagePolicy.isIrreversible(.run("/Users/me/.grand-line/bin/power", arguments: ["restart"])))
        XCTAssertFalse(UsagePolicy.isIrreversible(.run("/Users/me/.grand-line/bin/power", arguments: ["lock"])))
        XCTAssertFalse(UsagePolicy.isIrreversible(.run("/Users/me/.grand-line/bin/toggle", arguments: ["restart"])))
        XCTAssertTrue(UsagePolicy.isIrreversible(.quit(pid: 4, force: false)))
        XCTAssertFalse(UsagePolicy.isIrreversible(.open("/Applications/Safari.app")))
    }

    // MARK: Menu rows ask first

    func testTheQuestionColumnIsRead() throws {
        let entries = MenuFile.parse(["System/Restart\tpower restart\t\t\t!Press Return again to restart\nG/A\techo a\t?true\t✓true\t!\n"])
        XCTAssertEqual(entries[0].question, "Press Return again to restart")
        XCTAssertEqual(entries[0].confirmation, "Press Return again to restart")
        XCTAssertNil(entries[0].guardTest)
        XCTAssertEqual(entries[1].question, "")
        XCTAssertEqual(entries[1].confirmation, "Press Return again to run A", "a bare ! asks a plain question")
        XCTAssertEqual(entries[1].guardTest, "true")
        XCTAssertEqual(entries[1].checkTest, "true")
    }

    func testMenuRowsThatEndTheSessionAskFirstEvenWithoutTheColumn() throws {
        let restart = try menuRow("Mine/Reboot now\tpower restart")
        XCTAssertNotNil(restart.primary?.confirmation, "a local entry without ! still asks")
        XCTAssertNil(try menuRow("System/Lock\tpower lock").primary?.confirmation)
        XCTAssertNil(try menuRow("Toggle/Dark mode\ttoggle dark").primary?.confirmation)
    }

    func testTheShippedMenuAsksBeforeSleepLogOutRestartAndShutDown() throws {
        let text = try String(contentsOf: Self.repo.appendingPathComponent("config/grand-line/menu.tsv"), encoding: .utf8)
        let entries = MenuFile.parse([text])
        let system = entries.filter { $0.groups == ["System"] }
        XCTAssertEqual(Set(system.map(\.label)), ["Lock", "Sleep display", "Sleep", "Log out", "Restart", "Shut down"])
        for entry in system {
            let irreversible = ["Sleep", "Log out", "Restart", "Shut down"].contains(entry.label)
            XCTAssertEqual(entry.question != nil, irreversible, entry.path)
            XCTAssertEqual(entry.confirmation != nil, irreversible, entry.path)
        }
        let rows = MenuProvider.results(entries, states: nil).filter { $0.subtitle == "System" }
        for row in rows where row.title != "Lock" && row.title != "Sleep display" {
            XCTAssertNotNil(row.primary?.confirmation, row.title)
        }
    }

    func testTheGateHoldsAMenuRestartForASecondReturn() throws {
        let row = try menuRow("System/Restart\tpower restart\t\t\t!Press Return again to restart")
        var gate = ConfirmationGate()
        XCTAssertFalse(gate.shouldRun(row.primary!, on: row.id))
        XCTAssertEqual(gate.pending?.question, "Press Return again to restart")
        XCTAssertTrue(gate.shouldRun(row.primary!, on: row.id))
    }

    func testAnyRankedRowThatEndsTheSessionGetsAQuestion() {
        // A shortcut's row, an external provider's row, an old favourite: whatever made it.
        let shortcut = LaunchResult(id: "key:Caps + R", title: "Restart the Mac", icon: .symbol("keyboard"), section: .grandLine,
                                    actions: [LaunchAction("Run", symbol: "play", .shell("$HOME/.grand-line/bin/power restart")),
                                              .copy("Caps + R", title: "Copy keys")],
                                    providerID: "keybindings")
        let ranked = Ranker().rank(Make.matched([shortcut], "restart"), query: router.parse("restart"))
        XCTAssertEqual(ranked.first?.primary?.confirmation, "Press Return again to run Restart the Mac")
        XCTAssertNil(ranked.first?.secondary?.confirmation, "copying asks nothing")
    }

    // MARK: Learning never lifts them

    func testRowsThatAskFirstAreNotRecordedOrLearned() throws {
        let usage = UsageStore()
        let restart = try menuRow("System/Restart\tpower restart\t\t\t!Press Return again to restart")
        let query = router.parse("rest")
        usage.record(restart, query: query)
        XCTAssertNil(usage.abbreviation(for: query))
        XCTAssertTrue(usage.recents().isEmpty, "never in recents, where Return on an empty query would run it")
        XCTAssertEqual(usage.frecency(id: restart.id, query: query), 0)
    }

    func testALearnedRestartFromAnOldFileIsForgottenAndNeverLifted() throws {
        // usage.json from before: the menu's Restart without a question, learned for "rest".
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = LaunchResult(id: "menu:System/Restart", title: "Restart", subtitle: "System", icon: .symbol("power"), section: .grandLine,
                               actions: [LaunchAction("Run", symbol: "play", .shell("power restart"))], providerID: "menu")
        let writer = UsageStore(fileURL: url)
        writer.record(Make.row("Safari"), query: router.parse("saf"))
        try writer.save()
        try Self.inject(old, into: url, abbreviation: "rest")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("menu:System/Restart"), "the old file holds it")

        let usage = UsageStore(fileURL: url)
        XCTAssertNil(usage.abbreviation(for: router.parse("rest")))
        XCTAssertEqual(usage.recents().map(\.title), ["Safari"])
        XCTAssertTrue(usage.hasUnsavedChanges, "the cleaned file is written at the next save")
        try usage.save()
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("power restart"))
    }

    func testTheLearnedTierNeverLiftsARowThatAsksFirst() throws {
        let settings = LaunchResult(id: "setting.restart", title: "Restart", icon: .symbol("restart"), section: .system,
                                    actions: [LaunchAction("Restart", symbol: "restart", confirmation: "Press Return again to restart",
                                                           .run("/Users/me/.grand-line/bin/power", arguments: ["restart"]))],
                                    providerID: SettingsActionsProvider.providerID)
        let ranker = Ranker()
        let rows = Make.matched([settings], "rest")
        let key = ranker.key(for: rows[0], folded: "rest", frecencies: [settings.id: 1_000], learned: settings.id)
        XCTAssertFalse(key.learned)
        XCTAssertEqual(key.frecency, 0)
    }

    // MARK: Clipboard text never reaches usage.json

    func clip(_ text: String) -> LaunchResult {
        ClipboardHistory.results([ClipEntry(id: 7, text: text, app: "com.example.Notes")]).first!
    }

    func testClipboardEntriesAreNeverWritten() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let usage = UsageStore(fileURL: url)
        let secret = "clipboard text that must stay private"
        let row = clip(secret)
        usage.record(row, query: router.parse(":clip"))
        usage.toggleFavourite(row)
        XCTAssertTrue(usage.recents().isEmpty)
        XCTAssertTrue(usage.favourites().isEmpty)
        XCTAssertFalse(usage.isFavourite(row.id))
        usage.record(Make.row("Notes"), query: router.parse("no"))
        try usage.save()
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains(secret))
        XCTAssertFalse(raw.contains("hunt"), "nor what was typed to find it")
        XCTAssertFalse(raw.contains("clip:"))
    }

    func testClipboardEntriesInAnOldFileAreRemoved() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = UsageStore(fileURL: url)
        writer.record(Make.row("Notes"), query: router.parse("no"))
        try writer.save()
        try Self.inject(clip("old-secret-value"), into: url, abbreviation: ":old", favourite: true)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("old-secret-value"))
        let usage = UsageStore(fileURL: url)
        XCTAssertEqual(usage.recents().map(\.title), ["Notes"])
        XCTAssertTrue(usage.favourites().isEmpty)
        try usage.save()
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("old-secret-value"))
    }

    // MARK: Pids are never replayed

    func processRow() throws -> LaunchResult {
        let provider = ProcessProvider()
        provider.set([ProcessEntry(pid: 812, name: "Safari", bundlePath: "/Applications/Safari.app")])
        return try XCTUnwrap(provider.instantResults(for: LaunchQuery(raw: "quit safari")).first)
    }

    func testProcessRowsAreNeverRecordedOrFavourited() throws {
        let usage = UsageStore()
        let row = try processRow()
        usage.record(row, query: router.parse("quit safari"))
        usage.toggleFavourite(row)
        XCTAssertTrue(usage.recents().isEmpty)
        XCTAssertTrue(usage.favourites().isEmpty)
        XCTAssertNil(usage.abbreviation(for: router.parse("quit safari")))
        let menuItem = MenuBarItems.results([MenuBarItems.Item(path: ["File", "Close"], shortcut: nil)], app: "Safari", pid: 812)[0]
        usage.record(menuItem, query: router.parse("close"))
        XCTAssertTrue(usage.recents().isEmpty, "a menu item presses a pid too")
    }

    func testAQuitOnlyActsOnTheAppItWasMadeFor() throws {
        let row = try processRow()
        XCTAssertEqual(ProcessProvider.expectedName(of: row), "Safari")
        XCTAssertEqual(row.title, "Quit Safari")
        XCTAssertTrue(ProcessProvider.stillMatches(pid: 812, expected: "Safari", running: ProcessEntry(pid: 812, name: "Safari")))
        XCTAssertFalse(ProcessProvider.stillMatches(pid: 812, expected: "Safari", running: ProcessEntry(pid: 812, name: "Terminal")),
                       "the pid was reused by another app")
        XCTAssertFalse(ProcessProvider.stillMatches(pid: 812, expected: "Safari", running: nil), "it has quit")
        XCTAssertFalse(ProcessProvider.stillMatches(pid: 812, expected: "Safari", running: ProcessEntry(pid: 813, name: "Safari")))
    }

    func testProcessRowsInAnOldFileAreRemoved() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = UsageStore(fileURL: url)
        writer.record(Make.row("Notes"), query: router.parse("no"))
        try writer.save()
        // An old snapshot without its confirmation, recorded before the rule.
        var old = try processRow()
        old.actions = old.actions.map { var a = $0; a.confirmation = nil; return a }
        try Self.inject(old, into: url, abbreviation: "quit saf", favourite: true)
        let usage = UsageStore(fileURL: url)
        XCTAssertEqual(usage.recents().map(\.title), ["Notes"])
        XCTAssertTrue(usage.favourites().isEmpty)
        XCTAssertNil(usage.abbreviation(for: router.parse("quit saf")))
    }

    // MARK: Settings rows win over their menu copies

    func engine() -> SearchEngine {
        let settings = SettingsActionsProvider(paths: paths, runner: FakeMac())
        let menu = MenuProvider(paths: paths)
        let text = try? String(contentsOf: Self.repo.appendingPathComponent("config/grand-line/menu.tsv"), encoding: .utf8)
        menu.catalog.replace(MenuProvider.results(MenuFile.parse([text ?? ""]), states: nil))
        let keys = KeybindingsFile.provider(paths)
        keys.replace(KeybindingsFile.results(KeybindingsFile.parse(
            "Caps + Ctrl + N\tToggles\tDark and light mode\t$HOME/.grand-line/bin/toggle dark\n", local: "")))
        return SearchEngine(providers: [settings, menu, keys])
    }

    func testASettingsPhraseShowsTheSettingsRowOnTopAndNotTheMenuCopy() {
        let engine = engine()
        for (phrase, id) in [("dark mode", "setting.darkmode"), ("dark", "setting.darkmode"), ("dar", "setting.darkmode"),
                             ("hidden files", "setting.hiddenfiles"), ("wifi", "setting.wifi"), ("restart", "setting.restart"),
                             ("shut down", "setting.shutdown"), ("sleep display", "setting.displaysleep"), ("keep awake", "setting.keepawake")] {
            let rows = engine.instantRanked(engine.plan(phrase))
            XCTAssertEqual(rows.first?.id, id, phrase)
            XCTAssertEqual(rows.first?.providerID, SettingsActionsProvider.providerID, phrase)
            let copies = rows.filter { MenuProvider.settingDuplicated(by: $0) == id }
            XCTAssertTrue(copies.isEmpty, "\(phrase): \(copies.map(\.id))")
        }
    }

    func testMenuRowsStayWhenNoSettingsRowAnswers() {
        let engine = engine()
        let rows = engine.instantRanked(engine.plan("graphite"))
        XCTAssertEqual(rows.first?.id, "menu:Style/Graphite")
        let menuOnly = SearchEngine(providers: engine.providers.filter { $0.id != SettingsActionsProvider.providerID })
        let dark = menuOnly.instantRanked(menuOnly.plan("dark mode"))
        XCTAssertTrue(dark.contains { $0.id == "menu:Toggle/Dark mode" }, "with the settings source off the menu row is still there")
    }

    func testDuplicatesAreFoundByCommand() throws {
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("Toggle/Dark mode\ttoggle dark\t\t✓is_on dark")), "setting.darkmode")
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("Toggle/Microphone muted\ttoggle mic")), "setting.micmute")
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("System/Shut down\tpower shutdown")), "setting.shutdown")
        XCTAssertNil(MenuProvider.settingDuplicated(by: try menuRow("Toggle/Docker\ttoggle docker")))
        XCTAssertNil(MenuProvider.settingDuplicated(by: try menuRow("Style/Graphite\ttheme set graphite")))
    }

    func testThemeModeAndPrefixedCommandsAreDarkModesCopies() throws {
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("Style/Dark or light variant\ttheme mode toggle")), "setting.darkmode")
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("Mine/Dark\t$HOME/.grand-line/bin/theme mode dark")), "setting.darkmode")
        XCTAssertEqual(MenuProvider.settingDuplicated(by: try menuRow("Mine/Dark\tGRAND_LINE_QUIET=1 exec \"$HOME/.grand-line/bin/toggle\" dark")),
                       "setting.darkmode")
        XCTAssertNil(MenuProvider.settingDuplicated(by: try menuRow("Style/Pick a theme\ttheme pick")))
        XCTAssertNil(MenuProvider.settingDuplicated(by: try menuRow("Mine/Modes\tmode dark")))
    }

    /// Sight as it runs with ~/.grand-line linked to this repository: the
    /// shipped menu.tsv, keybindings.tsv and bin/ commands, System Settings'
    /// panes ("Appearance" answers "dark mode" too) and the settings rows.
    func shippedEngine() throws -> SearchEngine {
        let settings = SettingsActionsProvider(paths: paths, runner: FakeMac())
        let menu = MenuProvider(paths: paths)
        let menuText = try String(contentsOf: Self.repo.appendingPathComponent("config/grand-line/menu.tsv"), encoding: .utf8)
        menu.catalog.replace(MenuProvider.results(MenuFile.parse([menuText]), states: nil))
        let keys = KeybindingsFile.provider(paths)
        let keysText = try String(contentsOf: Self.repo.appendingPathComponent("config/grand-line/keybindings.tsv"), encoding: .utf8)
        let bindings = KeybindingsFile.parse(keysText, local: "")
        XCTAssertGreaterThan(bindings.count, 90, "the shipped shortcuts were read")
        keys.replace(KeybindingsFile.results(bindings))
        let commands = CommandsProvider(folder: Self.repo.appendingPathComponent("bin").path)
        commands.reload()
        return SearchEngine(providers: [settings, menu, commands, keys, SettingsPanes.provider()])
    }

    func testTheShippedFilesPutTheSettingsRowOnTopForEverySettingPhrase() throws {
        let engine = try shippedEngine()
        for (phrase, id) in [("dark mode", "setting.darkmode"), ("dark", "setting.darkmode"), ("light mode", "setting.darkmode"),
                             ("wifi", "setting.wifi"), ("hidden files", "setting.hiddenfiles"), ("mute", "setting.mute"),
                             ("mute mic", "setting.micmute")] {
            let plan = engine.plan(phrase)
            let rows = engine.instantRanked(plan)
            XCTAssertEqual(rows.first?.id, id, "\(phrase): \(rows.prefix(4).map(\.id))")
            XCTAssertEqual(rows.first?.providerID, SettingsActionsProvider.providerID, phrase)
            // What the window shows: the settings row as the top hit, the one Return runs.
            let groups = ResultGrouping.group(rows, topHit: plan.topHit, limitScale: plan.limitScale, layout: .standard)
            XCTAssertEqual(groups.first?.section, .topHit, phrase)
            XCTAssertEqual(groups.first?.rows.first?.id, id, phrase)
            // Nothing left that runs the same change another way.
            let copies = rows.filter { MenuProvider.settingDuplicated(by: $0) == id }
            XCTAssertTrue(copies.isEmpty, "\(phrase): \(copies.map(\.id))")
            // Typed a letter at a time, the row held on top for a shorter query never beats it.
            var hold = TopRowHold()
            var top: String?
            var ends = Array(phrase.indices.dropFirst())
            ends.append(phrase.endIndex)
            for end in ends {
                let partial = engine.plan(String(phrase[..<end]))
                top = hold.apply(engine.instantRanked(partial), query: partial.query).first?.id
            }
            XCTAssertEqual(top, id, "\(phrase), typed")
        }
    }

    func testAWholeSettingPhraseOutranksAnAliasOrAnExactTitleElsewhere() {
        let ranker = Ranker()
        let setting = LaunchResult(id: "setting.darkmode", title: "Dark mode", icon: .symbol("circle.lefthalf.filled"), section: .system,
                                   actions: [], providerID: SettingsActionsProvider.providerID,
                                   match: MatchInfo(alias: .exact, title: .exact, quality: 10_000))
        let aliased = LaunchResult(id: "app:/Applications/Dark.app", title: "Dark mode", icon: .symbol("app"), section: .apps,
                                   actions: [], providerID: "apps", match: MatchInfo(alias: .exact, title: .exact, quality: 20_000))
        let folded = "dark mode"
        let a = ranker.key(for: setting, folded: folded, frecencies: [:])
        let b = ranker.key(for: aliased, folded: folded, frecencies: [aliased.id: 1_000], learned: aliased.id)
        XCTAssertTrue(a.settingPhrase)
        XCTAssertFalse(b.settingPhrase)
        XCTAssertTrue(a < b)
        XCTAssertTrue(a.hasBetterTier(than: b), "the hold never keeps another row above it")
        var started = setting
        started.match = MatchInfo(title: .prefix, quality: 10_000)
        XCTAssertFalse(ranker.key(for: started, folded: "dark m", frecencies: [:]).settingPhrase, "a phrase still being typed is not whole")
    }

    // MARK: Helpers

    /// Adds a snapshot, its score, an abbreviation and (optionally) a
    /// favourite to a saved usage.json, as a file from an older Sight would hold.
    static func inject(_ row: LaunchResult, into url: URL, abbreviation: String, favourite: Bool = false) throws {
        let data = try Data(contentsOf: url)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoder = JSONEncoder()
        let snapshot = try JSONSerialization.jsonObject(with: encoder.encode(row))
        var snapshots = json["snapshots"] as? [String: Any] ?? [:]
        snapshots[row.id] = snapshot
        json["snapshots"] = snapshots
        var global = json["global"] as? [String: Any] ?? [:]
        global[row.id] = ["score": 5, "last": Date().timeIntervalSince1970 + 60, "count": 5]
        json["global"] = global
        var queries = json["queries"] as? [String: Any] ?? [:]
        queries[abbreviation] = [row.id: ["score": 5, "last": Date().timeIntervalSince1970, "count": 5]]
        json["queries"] = queries
        var abbreviations = json["abbreviations"] as? [String: Any] ?? [:]
        abbreviations[abbreviation] = ["id": row.id, "last": Date().timeIntervalSince1970, "challenges": 0]
        json["abbreviations"] = abbreviations
        if favourite {
            json["favourites"] = (json["favourites"] as? [String] ?? []) + [row.id]
        }
        // As Sight's own JSONEncoder writes ids: JSONSerialization would
        // otherwise escape "/" as "\/", and "menu:System/Restart" would not
        // read back as written.
        try JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes]).write(to: url)
    }
}
