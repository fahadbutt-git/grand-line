import XCTest
@testable import IcebergKit

/// The Pomodoro timer: phases and rounds, the long break, pause and resume
/// worked out from the end date, skip and reset, catching up after sleep,
/// its state file, its settings, and the command and URL that drive it.
final class PomodoroTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    let config = PomodoroConfig()

    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    // MARK: Phases and rounds

    func testAFreshTimerWaitsAtTheFirstFocusRound() {
        let t = PomodoroTimer(config: config)
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.status, .idle)
        XCTAssertEqual(t.remaining(at: t0), 25 * 60)
        XCTAssertEqual(t.clock(at: t0), "25:00")
        XCTAssertEqual(t.dots, [false, false, false, false])
        XCTAssertEqual(t.round, 1)
        XCTAssertFalse(t.isActive)
        XCTAssertTrue(t.isFresh(config: config))
    }

    func testFocusThenShortBreakWaitsWithoutAutoStart() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        XCTAssertEqual(t.status, .running)
        XCTAssertEqual(t.endsAt, at(25), "the end date is kept, not a count")
        XCTAssertEqual(t.clock(at: at(0.5)), "24:30")
        XCTAssertEqual(t.clock(at: t0.addingTimeInterval(0.4)), "25:00", "rounded up: a new phase shows its whole length")
        XCTAssertEqual(t.update(at: at(24.9), config: config), [], "nothing ends early")
        let ends = t.update(at: at(25), config: config)
        XCTAssertEqual(ends.count, 1)
        XCTAssertEqual(ends[0].finished, .focus)
        XCTAssertEqual(ends[0].next, .shortBreak)
        XCTAssertEqual(ends[0].at, at(25))
        XCTAssertFalse(ends[0].nextStarted)
        XCTAssertEqual(ends[0].title, "Focus done")
        XCTAssertEqual(ends[0].body, "Take a 5 min break.")
        XCTAssertEqual(t.phase, .shortBreak)
        XCTAssertEqual(t.status, .idle)
        XCTAssertEqual(t.remaining(at: at(40)), 5 * 60, "an idle phase does not count down")
        XCTAssertEqual(t.dots, [true, false, false, false])
        XCTAssertEqual(t.round, 1)
    }

    func testTheLongBreakComesAfterTheLastFocusRound() {
        let auto = PomodoroConfig(autoStart: true)
        var t = PomodoroTimer(config: auto)
        t.start(at: t0, config: auto)
        var phases: [PomodoroPhase] = []
        var now = t0
        for _ in 0..<9 {
            now = t.endsAt!
            let ends = t.update(at: now, config: auto)
            XCTAssertEqual(ends.count, 1)
            XCTAssertTrue(ends[0].nextStarted)
            phases.append(ends[0].next)
        }
        XCTAssertEqual(phases, [.shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus, .shortBreak])
        XCTAssertEqual(t.dots, [true, false, false, false], "the long break starts a new set")
        // Four focus rounds of 25, three short breaks of 5, a long break of 15, one more focus round.
        XCTAssertEqual(now, at(4 * 25 + 3 * 5 + 15 + 25))
    }

    func testTheLongBreakShowsEveryDotDone() {
        var t = PomodoroTimer(config: config)
        for _ in 0..<4 { t.skip(at: t0, config: config); if t.phase == .shortBreak { t.skip(at: t0, config: config) } }
        XCTAssertEqual(t.phase, .longBreak)
        XCTAssertEqual(t.dots, [true, true, true, true])
        XCTAssertEqual(t.round, 4)
        XCTAssertEqual(t.remaining(at: t0), 15 * 60)
        let end = t.skip(at: t0, config: config)
        XCTAssertEqual(end.body, "Time to focus for 25 min.")
        XCTAssertEqual(t.dots, [false, false, false, false])
    }

    func testRoundsBeforeTheLongBreakFollowTheSetting() {
        let two = PomodoroConfig(rounds: 2)
        var t = PomodoroTimer(config: two)
        XCTAssertEqual(t.skip(at: t0, config: two).next, .shortBreak)
        t.skip(at: t0, config: two)
        XCTAssertEqual(t.skip(at: t0, config: two).next, .longBreak)
        XCTAssertEqual(t.dots, [true, true])
    }

    // MARK: Pause, resume, toggle

    func testPauseAndResumeKeepTheTimeLeft() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        t.pause(at: at(10))
        XCTAssertEqual(t.status, .paused)
        XCTAssertNil(t.endsAt)
        XCTAssertEqual(t.remaining(at: at(60)), 15 * 60, "paused time does not count")
        XCTAssertEqual(t.update(at: at(60), config: config), [], "a paused phase never ends")
        t.resume(at: at(60))
        XCTAssertEqual(t.endsAt, at(75))
        XCTAssertEqual(t.clock(at: at(74.5)), "0:30")
        t.pause(at: at(70))
        t.start(at: at(80), config: config)
        XCTAssertEqual(t.endsAt, at(85), "start resumes a paused timer")
    }

    func testToggleStartsPausesAndResumes() {
        var t = PomodoroTimer(config: config)
        t.toggle(at: t0, config: config)
        XCTAssertEqual(t.status, .running)
        t.toggle(at: at(5), config: config)
        XCTAssertEqual(t.status, .paused)
        t.toggle(at: at(6), config: config)
        XCTAssertEqual(t.status, .running)
        XCTAssertEqual(t.endsAt, at(26))
    }

    func testStartWithMinutesIsAOneOffFocusRound() {
        var t = PomodoroTimer(config: config)
        t.skip(at: t0, config: config)
        XCTAssertEqual(t.phase, .shortBreak)
        t.start(at: t0, config: config, minutes: 50)
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.length, 50 * 60)
        XCTAssertEqual(t.endsAt, at(50))
        t.start(at: t0, config: config, minutes: 999)
        XCTAssertEqual(t.length, 180 * 60, "kept in range")
        t.update(at: at(180), config: config)
        XCTAssertEqual(t.remaining(at: at(200)), 5 * 60, "the round after a one-off uses the settings")
    }

    // MARK: Skip and reset

    func testSkipMovesOnAndKeepsRunning() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        let end = t.skip(at: at(3), config: config)
        XCTAssertTrue(end.skipped)
        XCTAssertFalse(end.shouldAnnounce(at: at(3)), "a skip is not announced")
        XCTAssertEqual(t.phase, .shortBreak)
        XCTAssertEqual(t.status, .running, "running carries on running")
        XCTAssertEqual(t.endsAt, at(8))
        XCTAssertEqual(t.dots, [true, false, false, false], "a skipped focus round counts")
        t.pause(at: at(4))
        t.skip(at: at(5), config: config)
        XCTAssertEqual(t.phase, .focus)
        XCTAssertEqual(t.status, .idle, "paused or idle waits at the next phase")
    }

    func testResetGoesBackToTheFirstRound() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        t.skip(at: at(1), config: config)
        t.skip(at: at(2), config: config)
        XCTAssertFalse(t.isFresh(config: config))
        t.reset(config: config)
        XCTAssertEqual(t, PomodoroTimer(config: config))
        XCTAssertTrue(t.isFresh(config: config))
    }

    // MARK: Sleep, wake and restarts

    func testWakeWorksOutTheTimeFromTheClock() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        // Asleep from minute 5 to minute 20: nothing ran meanwhile.
        XCTAssertEqual(t.update(at: at(20), config: config), [])
        XCTAssertEqual(t.clock(at: at(20)), "5:00")
        // Asleep through the end: the end is found on wake, at its planned time.
        let ends = t.update(at: at(31), config: config)
        XCTAssertEqual(ends.map(\.at), [at(25)])
        XCTAssertTrue(ends[0].shouldAnnounce(at: at(31)))
        XCTAssertFalse(ends[0].shouldAnnounce(at: at(25 + 11)), "an end long past is not announced")
    }

    func testAutoStartCatchesUpThroughSeveralPhases() {
        let auto = PomodoroConfig(autoStart: true)
        var t = PomodoroTimer(config: auto)
        t.start(at: t0, config: auto)
        // Focus 25, break 5, focus 25: the Mac wakes 10 minutes into the second break.
        let ends = t.update(at: at(25 + 5 + 25 + 1), config: auto)
        XCTAssertEqual(ends.map(\.next), [.shortBreak, .focus, .shortBreak])
        XCTAssertEqual(t.phase, .shortBreak)
        XCTAssertEqual(t.endsAt, at(25 + 5 + 25 + 5), "each phase starts at the planned end of the one before")
        XCTAssertEqual(t.dots, [true, true, false, false])
    }

    func testAClockFarAheadDoesNotSpin() {
        let auto = PomodoroConfig(focus: 1, shortBreak: 1, longBreak: 1, autoStart: true)
        var t = PomodoroTimer(config: auto)
        t.start(at: t0, config: auto)
        let ends = t.update(at: at(60 * 24 * 365), config: auto)
        XCTAssertLessThanOrEqual(ends.count, 500)
        XCTAssertEqual(t.status, .idle)
    }

    func testTheStateFileKeepsARunningTimer() throws {
        let folder = TempFolder()
        let file = folder.url.appendingPathComponent("state/pomodoro.json")
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        t.skip(at: at(1), config: config)
        try t.save(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("\"status\":\"running\""), text)
        XCTAssertTrue(text.contains("\"phase\":\"short_break\""), text)
        XCTAssertTrue(text.contains("\"ends_at\":"), "bin/iceberg reads ends_at: \(text)")
        let back = PomodoroTimer.load(from: file, config: config)
        XCTAssertEqual(back, t)
        XCTAssertEqual(back.endsAt, at(6))
        XCTAssertEqual(back.clock(at: at(4)), "2:00")
    }

    func testAMissingOrBrokenStateFileStartsFresh() {
        let folder = TempFolder()
        XCTAssertEqual(PomodoroTimer.load(from: folder.url.appendingPathComponent("none.json"), config: config),
                       PomodoroTimer(config: config))
        let broken = folder.write("broken.json", "{\"phase\": \"lunch\"")
        XCTAssertEqual(PomodoroTimer.load(from: broken, config: config), PomodoroTimer(config: config))
        // Values out of range are brought back within sense.
        let odd = PomodoroTimer.decode(Data("""
        {"phase":"focus","status":"running","length":5,"remaining":99999,"completed":40,"rounds":0}
        """.utf8))
        XCTAssertEqual(odd?.status, .paused, "running without an end date is held paused")
        XCTAssertEqual(odd?.length, 60)
        XCTAssertEqual(odd?.remaining(at: t0), 60)
        XCTAssertEqual(odd?.rounds, 1)
        XCTAssertEqual(odd?.completed, 1)
    }

    // MARK: Settings

    func testNewLengthsApplyToTheCurrentPhaseKeepingTimeRun() {
        var t = PomodoroTimer(config: config)
        t.start(at: t0, config: config)
        let longer = PomodoroConfig(focus: 45)
        t.apply(longer, previous: config, at: at(10))
        XCTAssertEqual(t.endsAt, at(45), "ten minutes in, 25 to 45 leaves 35")
        let shorter = PomodoroConfig(focus: 5)
        t.apply(shorter, previous: longer, at: at(10))
        XCTAssertEqual(t.endsAt, at(10), "shorter than the time run: it ends now")
        XCTAssertEqual(t.update(at: at(10), config: shorter).count, 1)
        // A change to another phase's length leaves this one alone.
        let before = t
        t.apply(PomodoroConfig(focus: 5, longBreak: 30), previous: shorter, at: at(11))
        XCTAssertEqual(t, before)
    }

    func testIdleTimerFollowsTheLengthAndAOneOffSurvivesARestart() {
        var idle = PomodoroTimer(config: config)
        idle.apply(PomodoroConfig(focus: 50), previous: nil, at: t0)
        XCTAssertEqual(idle.remaining(at: t0), 50 * 60, "a phase not yet begun takes the settings")
        var oneOff = PomodoroTimer(config: config)
        oneOff.start(at: t0, config: config, minutes: 30)
        oneOff.apply(PomodoroConfig(focus: 50), previous: nil, at: at(1))
        XCTAssertEqual(oneOff.endsAt, at(30), "the first settings after a restart do not change a running round")
    }

    func testFewerRoundsKeepTheDotsInRange() {
        var t = PomodoroTimer(config: config)
        for _ in 0..<3 { t.skip(at: t0, config: config); t.skip(at: t0, config: config) }
        XCTAssertEqual(t.completed, 3)
        t.apply(PomodoroConfig(rounds: 2), previous: config, at: t0)
        XCTAssertEqual(t.dots, [true, true])
    }

    func testConfigFromSettings() {
        let (s, issues) = IcebergSettings.parse("""
        pomodoro_focus = 50
        pomodoro_short_break = 10
        pomodoro_long_break = 500
        pomodoro_rounds = 3
        pomodoro_auto_start = true
        pomodoro_sound = false
        """)
        XCTAssertEqual(issues.count, 1, "the long break is brought into range: \(issues)")
        XCTAssertEqual(issues.first?.line, 3)
        XCTAssertEqual(issues.first?.severity, .warning)
        let c = PomodoroConfig(settings: s)
        XCTAssertEqual(c, PomodoroConfig(focus: 50, shortBreak: 10, longBreak: 120, rounds: 3, autoStart: true, sound: false))
        XCTAssertEqual(PomodoroConfig(settings: IcebergSettings()), PomodoroConfig())
        XCTAssertEqual(PomodoroConfig(), PomodoroConfig(focus: 25, shortBreak: 5, longBreak: 15, rounds: 4, autoStart: false, sound: true))
    }

    func testBadPomodoroSettingsWarnAndKeepTheDefaults() {
        let (s, issues) = IcebergSettings.parse("""
        pomodoro_focus = "25"
        pomodoro_rounds = 2.5
        pomodoro_sound = "yes"
        pomodoro_lenght = 3
        """)
        XCTAssertEqual(s.pomodoroFocus, 25)
        XCTAssertEqual(s.pomodoroRounds, 4)
        XCTAssertTrue(s.pomodoroSound)
        XCTAssertEqual(issues.map(\.line), [1, 2, 3, 4])
        XCTAssertTrue(issues.allSatisfy { $0.fix != nil })
    }

    func testABadValueOnReloadKeepsThePreviousOne() throws {
        let folder = TempFolder()
        let file = folder.write("iceberg.toml", "pomodoro_focus = 45\n")
        let first = IcebergSettings.reload(from: file, previous: nil)
        XCTAssertEqual(first.settings.pomodoroFocus, 45)
        folder.write("iceberg.toml", "pomodoro_focus = \"lots\"\n")
        let second = IcebergSettings.reload(from: file, previous: first.settings)
        XCTAssertEqual(second.settings.pomodoroFocus, 45)
    }

    func testFocusSteps() {
        XCTAssertEqual(PomodoroConfig(focus: 25).focus(steppedBy: 1), 30)
        XCTAssertEqual(PomodoroConfig(focus: 25).focus(steppedBy: -1), 20)
        XCTAssertEqual(PomodoroConfig(focus: 3).focus(steppedBy: -1), 1)
        XCTAssertEqual(PomodoroConfig(focus: 178).focus(steppedBy: 1), 180)
        XCTAssertEqual(PomodoroConfig.presets, [15, 25, 45, 50])
    }

    func testThePanelHasPomodoroAndANewInstallShowsIt() {
        XCTAssertEqual(PanelCatalog.builtin("pomodoro")?.placement, .section)
        XCTAssertNil(PanelCatalog.builtin("pomodoro")?.permission)
        XCTAssertEqual(PanelLayout(settings: IcebergSettings()).enabled, ["date", "now-playing", "today", "pomodoro"])
    }

    // MARK: Words

    func testNoticeWords() {
        let auto = PomodoroConfig(autoStart: true)
        var t = PomodoroTimer(config: auto)
        t.start(at: t0, config: auto)
        let end = t.update(at: at(25), config: auto)[0]
        XCTAssertEqual(end.body, "Your 5 min break has started.")
        let back = t.update(at: at(30), config: auto)[0]
        XCTAssertEqual(back.title, "Break over")
        XCTAssertEqual(back.body, "Focus for 25 min has started.")
        let hud = HUDEvent.pomodoro(end)
        XCTAssertEqual(hud.kind, .timer)
        XCTAssertEqual(hud.symbol, "cup.and.saucer.fill")
        XCTAssertEqual(hud.text, "Break")
        XCTAssertEqual(hud.tone, .good)
        XCTAssertEqual(HUDEvent.pomodoro(back).symbol, "timer")
        for text in [end.title, end.body, back.body, hud.label] {
            XCTAssertFalse(text.contains("\u{2014}"), "no long dashes: \(text)")
        }
    }

    func testClockAndSpokenTime() {
        XCTAssertEqual(PomodoroTimer.clock(0), "0:00")
        XCTAssertEqual(PomodoroTimer.clock(0.2), "0:01")
        XCTAssertEqual(PomodoroTimer.clock(59.5), "1:00")
        XCTAssertEqual(PomodoroTimer.clock(180 * 60), "180:00")
        XCTAssertEqual(PomodoroTimer.spoken(61), "1 minute 1 second")
        XCTAssertEqual(PomodoroTimer.spoken(25 * 60), "25 minutes")
        XCTAssertEqual(PomodoroTimer.spoken(9), "9 seconds")
    }

    // MARK: The command and the URL

    func testCommandWords() {
        XCTAssertEqual(PomodoroCommand.parse(action: "start"), .start(minutes: nil))
        XCTAssertEqual(PomodoroCommand.parse(action: "START", minutes: "25"), .start(minutes: 25))
        XCTAssertNil(PomodoroCommand.parse(action: "start", minutes: "0"))
        XCTAssertNil(PomodoroCommand.parse(action: "start", minutes: "181"))
        XCTAssertNil(PomodoroCommand.parse(action: "start", minutes: "ten"))
        XCTAssertEqual(PomodoroCommand.parse(action: "pause"), .pause)
        XCTAssertEqual(PomodoroCommand.parse(action: "resume"), .resume)
        XCTAssertEqual(PomodoroCommand.parse(action: "toggle"), .toggle)
        XCTAssertEqual(PomodoroCommand.parse(action: "reset"), .reset)
        XCTAssertEqual(PomodoroCommand.parse(action: "skip"), .skip)
        XCTAssertNil(PomodoroCommand.parse(action: "pause", minutes: "5"))
        XCTAssertNil(PomodoroCommand.parse(action: "lunch"))
    }

    func testCommandsDriveTheTimer() {
        var t = PomodoroTimer(config: config)
        PomodoroCommand.toggle.apply(to: &t, at: t0, config: config)
        XCTAssertEqual(t.status, .running)
        PomodoroCommand.pause.apply(to: &t, at: at(1), config: config)
        XCTAssertEqual(t.status, .paused)
        PomodoroCommand.resume.apply(to: &t, at: at(2), config: config)
        XCTAssertEqual(t.endsAt, at(26))
        XCTAssertEqual(PomodoroCommand.skip.apply(to: &t, at: at(3), config: config)?.next, .shortBreak)
        PomodoroCommand.start(minutes: 15).apply(to: &t, at: at(4), config: config)
        XCTAssertEqual(t.endsAt, at(19))
        PomodoroCommand.reset.apply(to: &t, at: at(5), config: config)
        XCTAssertEqual(t, PomodoroTimer(config: config))
    }

    func testURLs() {
        func url(_ s: String) -> URL { URL(string: s)! }
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/start")), .pomodoro(.start(minutes: nil)))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/start?minutes=25")), .pomodoro(.start(minutes: 25)))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/start/50")), .pomodoro(.start(minutes: 50)))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/pause")), .pomodoro(.pause))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/resume")), .pomodoro(.resume))
        XCTAssertEqual(URLCommand.parse(url("iceberg://Pomodoro/Toggle")), .pomodoro(.toggle))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/reset")), .pomodoro(.reset))
        XCTAssertEqual(URLCommand.parse(url("iceberg://pomodoro/skip")), .pomodoro(.skip))
        XCTAssertNil(URLCommand.parse(url("iceberg://pomodoro")))
        XCTAssertNil(URLCommand.parse(url("iceberg://pomodoro/start?minutes=900")))
        XCTAssertNil(URLCommand.parse(url("iceberg://pomodoro/start/5/6")))
        XCTAssertNil(URLCommand.parse(url("iceberg://pomodoro/explode")))
    }

    func testBinIcebergUsesTheSameURLsAndStateFile() throws {
        let script = try String(contentsOf: repoFolder.appendingPathComponent("bin/iceberg"), encoding: .utf8)
        XCTAssertTrue(script.contains("pomodoro/start?minutes="))
        XCTAssertTrue(script.contains("iceberg/pomodoro.json"))
        XCTAssertTrue(IcebergPaths().pomodoroFile.path.hasSuffix(".local/state/grand-line/iceberg/pomodoro.json"))
        for action in ["pause", "resume", "toggle", "reset", "skip"] {
            XCTAssertNotNil(URLCommand.parse(URL(string: "iceberg://pomodoro/\(action)")!), action)
            XCTAssertTrue(script.contains(action), action)
        }
    }
}
