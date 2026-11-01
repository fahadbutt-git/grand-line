import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Runs a block of disk reads at the throttled I/O tier on the calling thread
/// (`setiopolicy_np`), as Spotlight and Time Machine read in the background:
/// the reads wait whenever another app needs the disk. The thread's earlier
/// policy is put back afterwards.
public enum ThrottledIO {
    public static func run<T>(_ throttled: Bool, _ body: () -> T) -> T {
        #if canImport(Darwin)
        guard throttled else { return body() }
        let before = getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)
        _ = setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, IOPOL_THROTTLE)
        defer { if before >= 0 { _ = setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD, before) } }
        return body()
        #else
        return body()
        #endif
    }

    /// The calling thread's disk policy, for tests.
    public static var currentPolicy: Int32 {
        #if canImport(Darwin)
        return getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_THREAD)
        #else
        return -1
        #endif
    }

    /// The throttled tier's value.
    public static var throttledPolicy: Int32 {
        #if canImport(Darwin)
        return IOPOL_THROTTLE
        #else
        return -1
        #endif
    }
}
