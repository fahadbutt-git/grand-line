import XCTest
@testable import IcebergKit

/// Now Playing robustness: the adapter's health check, the AppleScript
/// fallback for Music and Spotify, and what Settings says when neither works.
final class MediaHealthTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 3_000_000)

    func testAdapterCheckResults() {
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: 0, stderr: "", timedOut: false, launchError: nil), .healthy)
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: 1, stderr: "Test client path is missing\n", timedOut: false, launchError: nil),
                       .inconclusive)
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: 1, stderr: "Failed to load framework: /x\n", timedOut: false, launchError: nil),
                       .broken("Failed to load framework: /x"))
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: nil, stderr: "", timedOut: true, launchError: nil),
                       .broken("the check did not answer"))
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: 2, stderr: "", timedOut: false, launchError: nil),
                       .broken("the check ended with status 2"))
        XCTAssertEqual(AdapterCheck.evaluate(exitCode: nil, stderr: "", timedOut: false, launchError: "Could not start"),
                       .broken("Could not start"))
    }

    func testHealthyAdapterIsUsed() {
        var h = MediaHealth(adapterBundled: true)
        XCTAssertEqual(h.source, .adapter, "used until a check says otherwise")
        XCTAssertTrue(h.checkDue(at: t0))
        h.record(.healthy, at: t0)
        XCTAssertEqual(h.source, .adapter)
        XCTAssertNil(h.fix)
        XCTAssertFalse(h.checkDue(at: t0.addingTimeInterval(60)))
        XCTAssertTrue(h.checkDue(at: t0.addingTimeInterval(MediaHealth.checkInterval)))
        h.record(.inconclusive, at: t0)
        XCTAssertEqual(h.source, .adapter, "nothing playing is not a fault")
    }

    func testBrokenAdapterFallsBackToAppleScript() {
        var h = MediaHealth(adapterBundled: true)
        h.record(.broken("Symbol not found"), at: t0)
        XCTAssertEqual(h.source, .adapter, "one failed check is not enough")
        h.record(.broken("Symbol not found"), at: t0.addingTimeInterval(30))
        XCTAssertEqual(h.source, .appleScript)
        XCTAssertTrue(h.summary.hasPrefix("Music and Spotify only"))
        XCTAssertTrue(h.summary.contains("Symbol not found"))
        h.appleScript = .working
        XCTAssertEqual(h.source, .appleScript)
        // A later check that passes brings the adapter back.
        h.record(.healthy, at: t0.addingTimeInterval(300))
        XCTAssertEqual(h.source, .adapter)
    }

    func testStreamGivingUpFallsBackUntilAHealthyCheck() {
        var h = MediaHealth(adapterBundled: true)
        h.streamGaveUp = true
        XCTAssertEqual(h.source, .appleScript)
        h.record(.inconclusive, at: t0)
        XCTAssertEqual(h.source, .appleScript)
        h.record(.healthy, at: t0)
        XCTAssertEqual(h.source, .adapter)
        XCTAssertFalse(h.streamGaveUp)
    }

    func testNeitherWorkingSaysWhatToDo() {
        var h = MediaHealth(adapterBundled: true)
        h.record(.broken("x"), at: t0)
        h.record(.broken("x"), at: t0.addingTimeInterval(30))
        h.appleScript = .denied
        XCTAssertEqual(h.source, .none)
        XCTAssertTrue(h.summary.hasPrefix("Not working"))
        XCTAssertTrue(h.fix?.contains("Automation") ?? false)
        h.appleScript = .failed("error -2700")
        XCTAssertEqual(h.source, .none)
        XCTAssertTrue(h.summary.contains("error -2700"))
    }

    func testWithoutTheAdapter() {
        let h = MediaHealth(adapterBundled: false)
        XCTAssertEqual(h.source, .appleScript)
        XCTAssertFalse(h.checkDue(at: t0))
        XCTAssertTrue(h.fix?.contains("build") ?? false)
    }

    func testAppleScriptErrors() {
        XCTAssertEqual(AppleScriptStatus.from(errorNumber: nil, message: nil), .working)
        XCTAssertEqual(AppleScriptStatus.from(errorNumber: -1743, message: "Not authorised"), .denied)
        XCTAssertEqual(AppleScriptStatus.from(errorNumber: -600, message: "not running"), .working)
        XCTAssertEqual(AppleScriptStatus.from(errorNumber: -2700, message: "odd"), .failed("odd"))
    }

    func testSpotifyAnswer() throws {
        let p = try XCTUnwrap(AppleScriptNowPlaying.payload(
            from: "playing\tSo What\tMiles Davis\tKind of Blue\t562000\t12,5\n", player: AppleScriptNowPlaying.spotify, now: t0))
        var state = NowPlayingState()
        state.apply(payload: p, diff: false)
        XCTAssertEqual(state.title, "So What")
        XCTAssertEqual(state.artist, "Miles Davis")
        XCTAssertEqual(state.album, "Kind of Blue")
        XCTAssertEqual(state.duration, 562, "Spotify gives milliseconds")
        XCTAssertEqual(state.elapsed, 12.5, "a comma decimal is read")
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(state.position(at: t0.addingTimeInterval(2)), 14.5)
    }

    func testMusicAnswer() throws {
        let p = try XCTUnwrap(AppleScriptNowPlaying.payload(
            from: "paused\tSong\tmissing value\t\t215.3\t0", player: AppleScriptNowPlaying.music, now: t0))
        var state = NowPlayingState()
        state.apply(payload: p, diff: false)
        XCTAssertEqual(state.duration, 215.3)
        XCTAssertNil(state.artist)
        XCTAssertNil(state.album)
        XCTAssertFalse(state.isPlaying)
    }

    func testStoppedAndNotRunning() {
        XCTAssertEqual(AppleScriptNowPlaying.payload(from: "stopped", player: AppleScriptNowPlaying.music), [:])
        XCTAssertNil(AppleScriptNowPlaying.payload(from: "", player: AppleScriptNowPlaying.music))
        XCTAssertNil(AppleScriptNowPlaying.payload(from: "garbage", player: AppleScriptNowPlaying.music))
    }

    func testScriptsNeverOpenThePlayer() {
        for player in AppleScriptNowPlaying.players {
            let script = AppleScriptNowPlaying.script(for: player)
            XCTAssertTrue(script.hasPrefix("if application \"\(player.name)\" is running then"), script)
        }
    }

    /// One slow or failed check (perl loading after wake) must not stop a
    /// working stream: it takes two failures in a row, and a quiet stream.
    func testOneFailedCheckKeepsTheAdapter() {
        var h = MediaHealth(adapterBundled: true)
        h.record(.healthy, at: t0)
        h.record(.broken("the check did not answer"), at: t0.addingTimeInterval(300))
        XCTAssertEqual(h.source, .adapter)
        XCTAssertNil(h.adapterProblem, "not reported while it still counts as working")
        // The next check comes soon, to confirm or clear it.
        XCTAssertEqual(h.nextCheckDelay, MediaHealth.recheckAfterFailure)
        XCTAssertTrue(h.checkDue(at: t0.addingTimeInterval(300 + MediaHealth.recheckAfterFailure)))
        // A pass clears it.
        h.record(.inconclusive, at: t0.addingTimeInterval(330))
        XCTAssertEqual(h.source, .adapter)
        XCTAssertEqual(h.brokenInARow, 0)
        XCTAssertEqual(h.nextCheckDelay, MediaHealth.checkInterval)
        // Two in a row set it aside, and the usual interval applies again.
        h.record(.broken("x"), at: t0.addingTimeInterval(600))
        h.record(.broken("x"), at: t0.addingTimeInterval(630))
        XCTAssertEqual(h.source, .appleScript)
        XCTAssertEqual(h.nextCheckDelay, MediaHealth.checkInterval)
        h.record(.healthy, at: t0.addingTimeInterval(930))
        XCTAssertEqual(h.source, .adapter)
    }

    func testAStreamThatDeliversIsNotStopped() {
        var h = MediaHealth(adapterBundled: true)
        let now = t0.addingTimeInterval(1000)
        h.record(.broken("x"), at: now, streamDataAt: now.addingTimeInterval(-60))
        h.record(.broken("x"), at: now.addingTimeInterval(30), streamDataAt: now.addingTimeInterval(-60))
        XCTAssertEqual(h.source, .adapter, "the stream delivered a minute ago")
        XCTAssertEqual(h.nextCheckDelay, MediaHealth.checkInterval, "no rapid rechecks while it streams")
        // Quiet for longer than streamFreshFor: the checks win.
        let later = now.addingTimeInterval(MediaHealth.streamFreshFor + 60)
        h.record(.broken("x"), at: later, streamDataAt: now.addingTimeInterval(-60))
        XCTAssertEqual(h.source, .appleScript)
    }

    /// The AppleScript fallback runs in osascript with a time limit, off the
    /// main thread; what it says is read here.
    func testAppleScriptCallOutcomes() {
        var ok = CommandResult()
        ok.exitCode = 0
        ok.stdout = "playing\tSong\n"
        XCTAssertEqual(AppleScriptCall.outcome(of: ok), .init(output: "playing\tSong", status: .working))

        var denied = CommandResult()
        denied.exitCode = 1
        denied.stderr = "0:20: execution error: Not authorized to send Apple events to Music. (-1743)\n"
        XCTAssertEqual(AppleScriptCall.outcome(of: denied).status, .denied)
        XCTAssertNil(AppleScriptCall.outcome(of: denied).output)

        var hung = CommandResult()
        hung.timedOut = true
        XCTAssertEqual(AppleScriptCall.outcome(of: hung), .init(output: nil, status: nil),
                       "a timeout (the consent prompt waiting) says nothing about access")

        var odd = CommandResult()
        odd.exitCode = 1
        odd.stderr = "something broke"
        XCTAssertEqual(AppleScriptCall.outcome(of: odd).status, .failed("something broke"))

        XCTAssertEqual(AppleScriptCall.errorNumber(fromStderr: "x (-1712)"), -1712)
        XCTAssertNil(AppleScriptCall.errorNumber(fromStderr: "no number"))
    }

    func testAppleScriptCommandQuotesEachLine() {
        let cmd = AppleScriptCall.command(for: "with timeout of 2 seconds\ntell application \"Music\" to play\nend timeout")
        XCTAssertEqual(cmd, "/usr/bin/osascript -e 'with timeout of 2 seconds' -e 'tell application \"Music\" to play' -e 'end timeout'")
        XCTAssertEqual(AppleScriptCall.command(for: "say \"it's\""), "/usr/bin/osascript -e 'say \"it'\\''s\"'")
    }

    func testScriptsHaveTheirOwnTimeout() {
        for player in AppleScriptNowPlaying.players {
            let script = AppleScriptNowPlaying.script(for: player)
            XCTAssertTrue(script.contains("with timeout of 2 seconds"), script)
            XCTAssertLessThan(2, AppleScriptCall.timeout)
        }
    }

    #if os(macOS)
    /// A script that does not answer is cut off by the process limit.
    func testAHungScriptIsCutOff() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/osascript") else { throw XCTSkip("no osascript") }
        let started = Date()
        let outcome = AppleScriptCall.run("delay 30", timeout: 1)
        XCTAssertNil(outcome.status)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }
    #endif
}
