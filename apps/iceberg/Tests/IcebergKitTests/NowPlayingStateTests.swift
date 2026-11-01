import XCTest
@testable import IcebergKit

final class NowPlayingStateTests: XCTestCase {
    func testFullThenDiffUpdates() {
        var s = NowPlayingState()
        XCTAssertTrue(s.apply(line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.example.player","playing":true,"title":"Song A","artist":"Band","duration":200,"elapsedTime":10,"timestamp":"2026-01-01T00:00:00Z"}}"#))
        XCTAssertEqual(s.title, "Song A")
        XCTAssertEqual(s.artist, "Band")
        XCTAssertTrue(s.isPlaying)
        XCTAssertTrue(s.hasMedia)
        XCTAssertEqual(s.bundleIdentifier, "com.example.player")

        s.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#)
        XCTAssertEqual(s.title, "Song A")
        XCTAssertFalse(s.isPlaying)
        XCTAssertNil(s.artist)

        s.apply(line: #"{"type":"data","diff":false,"payload":{}}"#)
        XCTAssertFalse(s.hasMedia)
    }

    func testParentBundleWins() {
        var s = NowPlayingState()
        s.apply(line: #"{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.example.webkit","parentApplicationBundleIdentifier":"com.example.browser","title":"Clip","playing":true}}"#)
        XCTAssertEqual(s.bundleIdentifier, "com.example.browser")
    }

    func testIgnoresOtherLines() {
        var s = NowPlayingState()
        XCTAssertFalse(s.apply(line: "not json"))
        XCTAssertFalse(s.apply(line: #"{"type":"log","payload":{}}"#))
        XCTAssertFalse(s.apply(line: #"[1,2]"#))
    }

    func testPositionCountsOnWhilePlaying() {
        var s = NowPlayingState()
        s.apply(payload: ["title": .string("T"), "playing": .bool(true), "duration": .number(100),
                          "elapsedTime": .number(10), "timestamp": .string("2026-01-01T00:00:00Z")], diff: false)
        let start = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        XCTAssertEqual(s.position(at: start.addingTimeInterval(5))!, 15, accuracy: 0.001)
        XCTAssertEqual(s.position(at: start.addingTimeInterval(500))!, 100, accuracy: 0.001)
        s.apply(payload: ["playing": .bool(false)], diff: true)
        XCTAssertEqual(s.position(at: start.addingTimeInterval(50))!, 10, accuracy: 0.001)
    }

    func testEpochTimestamps() {
        let s = NowPlayingState(fields: ["timestamp": .number(1_700_000_000)])
        XCTAssertEqual(s.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        let micros = NowPlayingState(fields: ["timestamp": .number(1_700_000_000_000_000)])
        XCTAssertEqual(micros.timestamp!.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    func testArtworkChangeDetection() {
        let a = NowPlayingState(fields: ["artworkData": .string("AAAA")])
        var b = a
        b.apply(payload: ["title": .string("x")], diff: true)
        XCTAssertFalse(b.artworkDiffers(from: a))
        b.apply(payload: ["artworkData": .string("BBBB")], diff: true)
        XCTAssertTrue(b.artworkDiffers(from: a))
    }

    func testLineBufferKeepsPartialLines() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("{\"a\":".utf8)), [])
        XCTAssertEqual(buffer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8)), ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(buffer.append(Data(":3}\n\n".utf8)), ["{\"c\":3}"])
    }

    /// A line over the limit is dropped whole: its tail, after the buffer
    /// overflowed, must not come out as a line of its own.
    func testOverlongLineIsDroppedWhole() {
        var buffer = LineBuffer()
        buffer.maxLineBytes = 16
        XCTAssertEqual(buffer.append(Data("{\"ok\":1}\n{\"art\":\"AAAAAAAAAAAA".utf8)), ["{\"ok\":1}"])
        XCTAssertEqual(buffer.append(Data("AAAAAAAAAAAAAAAA".utf8)), [], "still inside the long line")
        XCTAssertEqual(buffer.append(Data("AAAA==\"}\n{\"b\":2}\n".utf8)), ["{\"b\":2}"], "the tail is not a line")
        // A long line arriving whole in one chunk is dropped too.
        XCTAssertEqual(buffer.append(Data("\(String(repeating: "x", count: 40))\n{\"c\":3}\n".utf8)), ["{\"c\":3}"])
        // And the buffer is back to normal afterwards.
        XCTAssertEqual(buffer.append(Data("{\"d\":".utf8)), [])
        XCTAssertEqual(buffer.append(Data("4}\n".utf8)), ["{\"d\":4}"])
    }

    func testPlayerNotifications() {
        let p = PlayerNotification.payload(bundleIdentifier: "com.spotify.client",
                                           info: ["Name": "Track", "Artist": "Band", "Player State": "Playing", "Duration": 180_000, "Playback Position": 12.5])
        var s = NowPlayingState()
        s.apply(payload: p, diff: false)
        XCTAssertEqual(s.title, "Track")
        XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.duration, 180)
        XCTAssertEqual(s.elapsed, 12.5)

        let music = PlayerNotification.payload(bundleIdentifier: "com.apple.Music",
                                               info: ["Name": "Other", "Player State": "Paused", "Total Time": 90_000])
        XCTAssertEqual(music["duration"], .number(90))
        XCTAssertEqual(music["playing"], .bool(false))
        XCTAssertEqual(PlayerNotification.payload(bundleIdentifier: "com.apple.Music", info: ["Player State": "Stopped"]), [:])
        XCTAssertEqual(PlayerNotification.bundleIdentifier(forNotification: PlayerNotification.spotify), "com.spotify.client")
        XCTAssertNil(PlayerNotification.bundleIdentifier(forNotification: "other"))
    }
}
