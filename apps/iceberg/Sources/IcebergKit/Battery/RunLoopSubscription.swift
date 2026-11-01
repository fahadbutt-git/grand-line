#if canImport(Darwin)
import Foundation
import CoreFoundation

/// Owns a run-loop source whose C callback carries a raw context pointer
/// (IOKit's power-source notification, for one). The context handed to the
/// maker is this object, unretained. `cancel()` and deinit remove and
/// invalidate the source before the object goes, so a callback can never
/// reach freed memory, and one turned off and on again leaves no second
/// source behind.
///
/// Make, cancel and free it on the thread whose run loop it joins (the main
/// thread for the app), which is also where the callback runs.
public final class RunLoopSubscription: @unchecked Sendable {
    private var source: CFRunLoopSource?
    private let runLoop: CFRunLoop
    private let mode: CFRunLoopMode
    private let onFire: () -> Void

    /// `make` gets the context pointer to pass to the C API and returns the
    /// source (retained), or nil when the API offers none.
    public init(runLoop: CFRunLoop = CFRunLoopGetMain(),
                mode: CFRunLoopMode = .commonModes,
                make: (UnsafeMutableRawPointer) -> CFRunLoopSource?,
                onFire: @escaping () -> Void) {
        self.runLoop = runLoop
        self.mode = mode
        self.onFire = onFire
        if let src = make(Unmanaged.passUnretained(self).toOpaque()) {
            CFRunLoopAddSource(runLoop, src, mode)
            source = src
        }
    }

    /// True while the source is on the run loop.
    public var isActive: Bool { source != nil }

    /// The source, for tests.
    public var currentSource: CFRunLoopSource? { source }

    /// Removes and invalidates the source. Safe to call more than once.
    public func cancel() {
        guard let src = source else { return }
        source = nil
        CFRunLoopRemoveSource(runLoop, src, mode)
        CFRunLoopSourceInvalidate(src)
    }

    /// What the C callback calls with the context it was given.
    public static func fire(context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        let me = Unmanaged<RunLoopSubscription>.fromOpaque(context).takeUnretainedValue()
        if me.source != nil { me.onFire() }
    }

    deinit { cancel() }
}
#endif
