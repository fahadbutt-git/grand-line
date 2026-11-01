#if canImport(Darwin)
import XCTest
import CoreFoundation
@testable import IcebergKit

/// The Battery widget's power-source callback goes through a
/// RunLoopSubscription: once it is cancelled or freed, its source is off the
/// run loop and a callback never reaches it.
final class RunLoopSubscriptionTests: XCTestCase {
    final class Count { var n = 0 }

    /// A plain version-0 source standing in for IOKit's, whose perform
    /// callback hands its context to RunLoopSubscription.fire.
    private func makeSource(_ context: UnsafeMutableRawPointer) -> CFRunLoopSource? {
        var ctx = CFRunLoopSourceContext(
            version: 0, info: context, retain: nil, release: nil, copyDescription: nil,
            equal: nil, hash: nil, schedule: nil, cancel: nil,
            perform: { info in RunLoopSubscription.fire(context: info) })
        return CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &ctx)
    }

    private func spin() { _ = CFRunLoopRunInMode(.defaultMode, 0.05, false) }

    func testFiresWhileActive() throws {
        let count = Count()
        let sub = RunLoopSubscription(runLoop: CFRunLoopGetCurrent(), mode: .defaultMode,
                                      make: makeSource, onFire: { count.n += 1 })
        let src = try XCTUnwrap(sub.currentSource)
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetCurrent(), src, .defaultMode))
        CFRunLoopSourceSignal(src)
        spin()
        XCTAssertEqual(count.n, 1)
    }

    func testCancelRemovesTheSource() throws {
        let count = Count()
        let sub = RunLoopSubscription(runLoop: CFRunLoopGetCurrent(), mode: .defaultMode,
                                      make: makeSource, onFire: { count.n += 1 })
        let src = try XCTUnwrap(sub.currentSource)
        sub.cancel()
        sub.cancel()  // twice is harmless
        XCTAssertFalse(sub.isActive)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetCurrent(), src, .defaultMode))
        XCTAssertFalse(CFRunLoopSourceIsValid(src))
        CFRunLoopSourceSignal(src)
        spin()
        XCTAssertEqual(count.n, 0)
    }

    /// Turning the widget off lets it go: the source must leave with it.
    func testFreeingRemovesTheSource() throws {
        let count = Count()
        var src: CFRunLoopSource?
        weak var gone: RunLoopSubscription?
        do {
            let sub = RunLoopSubscription(runLoop: CFRunLoopGetCurrent(), mode: .defaultMode,
                                          make: makeSource, onFire: { count.n += 1 })
            src = sub.currentSource
            gone = sub
        }
        XCTAssertNil(gone)
        let s = try XCTUnwrap(src)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetCurrent(), s, .defaultMode))
        CFRunLoopSourceSignal(s)
        spin()
        XCTAssertEqual(count.n, 0)
    }

    /// Off and on again: one source, not two.
    func testOffAndOnLeavesOneSource() {
        let count = Count()
        let first = RunLoopSubscription(runLoop: CFRunLoopGetCurrent(), mode: .defaultMode,
                                        make: makeSource, onFire: { count.n += 1 })
        first.cancel()
        let second = RunLoopSubscription(runLoop: CFRunLoopGetCurrent(), mode: .defaultMode,
                                         make: makeSource, onFire: { count.n += 10 })
        if let a = first.currentSource { CFRunLoopSourceSignal(a) }
        if let b = second.currentSource { CFRunLoopSourceSignal(b) }
        spin()
        XCTAssertEqual(count.n, 10)
    }

    func testNoSourceIsInactive() {
        let sub = RunLoopSubscription(make: { _ in nil }, onFire: {})
        XCTAssertFalse(sub.isActive)
        sub.cancel()
    }
}
#endif
