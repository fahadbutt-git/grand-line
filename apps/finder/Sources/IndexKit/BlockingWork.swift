import Foundation

/// Runs blocking work (reading a snapshot from disk, walking an app's menus,
/// reading app bundles) on a Dispatch queue and awaits it.
///
/// Swift's concurrency pool has only as many threads as the Mac has cores.
/// Work that blocks a thread for seconds there, run from `Task.detached` at
/// launch, leaves the searches typed meanwhile waiting for a free thread, so
/// the first results after a launch came seconds late. Dispatch adds threads
/// for blocked work instead.
public enum BlockingWork {
    public static func run<T: Sendable>(
        qos: DispatchQoS.QoSClass = .utility, _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
        }
    }

    /// Starts blocking work without waiting for it.
    public static func start(qos: DispatchQoS.QoSClass = .utility, _ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: qos).async(execute: work)
    }
}
