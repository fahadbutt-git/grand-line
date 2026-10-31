import XCTest
@testable import IndexKit

/// Blocking work on Dispatch leaves the concurrency pool free, so a search
/// started meanwhile is not held up (the first results after Sight launched).
final class BlockingWorkTests: XCTestCase {
    func testRunReturnsTheWorksValue() async {
        let value = await BlockingWork.run { 6 * 7 }
        XCTAssertEqual(value, 42)
    }

    func testBlockedWorkLeavesThePoolFree() async {
        let release = DispatchSemaphore(value: 0)
        let blocked = ProcessInfo.processInfo.activeProcessorCount * 2
        for _ in 0..<blocked {
            BlockingWork.start { _ = release.wait(timeout: .now() + 5) }
        }
        let started = Date()
        let answer = await Task.detached(priority: .userInitiated) { 1 + 1 }.value
        let elapsed = Date().timeIntervalSince(started)
        for _ in 0..<blocked { release.signal() }
        XCTAssertEqual(answer, 2)
        XCTAssertLessThan(elapsed, 1, "a task waited for the blocked work")
    }
}
