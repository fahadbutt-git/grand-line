import XCTest
@testable import IcebergKit

/// iceberg:// URLs, and the queue that holds them during a cold launch
/// (AppKit can deliver the URL before the app has finished launching).
final class URLCommandTests: XCTestCase {
    func url(_ s: String) -> URL { URL(string: s)! }

    func testParse() {
        XCTAssertEqual(URLCommand.parse(url("iceberg://toggle")), .toggle)
        XCTAssertEqual(URLCommand.parse(url("iceberg://open")), .open)
        XCTAssertEqual(URLCommand.parse(url("ICEBERG://Close")), .close)
        XCTAssertEqual(URLCommand.parse(url("denden://reload")), .reload, "the former scheme still works")
        XCTAssertEqual(URLCommand.parse(url("iceberg://settings")), .settings)
        XCTAssertEqual(URLCommand.parse(url("iceberg://trigger/weather")), .trigger(["weather"]))
        XCTAssertEqual(URLCommand.parse(url("iceberg://trigger/a/b")), .trigger(["a", "b"]), "bin/iceberg sends several at once")
        XCTAssertEqual(URLCommand.parse(url("iceberg://trigger?widget=x&widget=y")), .trigger(["x", "y"]))
        XCTAssertNil(URLCommand.parse(url("iceberg://trigger")), "no name, nothing to run")
        XCTAssertNil(URLCommand.parse(url("iceberg://explode")))
        XCTAssertNil(URLCommand.parse(url("https://open")))
    }

    func testURLsBeforeLaunchWaitAndRunInOrder() {
        var q = LaunchQueue()
        XCTAssertNil(q.receive(url("iceberg://trigger/weather")), "queued, not run, before setup")
        XCTAssertNil(q.receive(url("iceberg://open")))
        XCTAssertNil(q.receive(url("https://elsewhere")))
        XCTAssertEqual(q.becomeReady(), [.trigger(["weather"]), .open])
        XCTAssertTrue(q.isReady)
        XCTAssertEqual(q.receive(url("iceberg://close")), .close, "after setup, at once")
        XCTAssertEqual(q.becomeReady(), [], "nothing replayed twice")
    }

    func testABurstBeforeLaunchIsCapped() {
        var q = LaunchQueue()
        for _ in 0..<(LaunchQueue.limit + 10) { _ = q.receive(url("iceberg://toggle")) }
        XCTAssertEqual(q.becomeReady().count, LaunchQueue.limit)
    }
}
