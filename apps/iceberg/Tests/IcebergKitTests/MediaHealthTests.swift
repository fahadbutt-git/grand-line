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
}
