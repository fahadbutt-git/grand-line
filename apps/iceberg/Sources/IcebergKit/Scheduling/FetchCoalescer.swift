import Foundation

/// One background fetch at a time, however many times it is asked for.
///
/// A burst of change notices (a calendar sync) while a fetch runs folds
/// into one more fetch after it, never a queue of them, and never two at
/// once. Kept on the main thread by its owner.
public struct FetchCoalescer: Equatable, Sendable {
    public private(set) var running = false
    public private(set) var again = false
    /// Bumped by every fetch started; a result from an older one is stale.
    public private(set) var generation = 0

    public init() {}

    /// A fetch is wanted. Returns the generation to start now, or nil when
    /// one is running (it runs once more when that one finishes).
    public mutating func request() -> Int? {
        if running {
            again = true
            return nil
        }
        running = true
        generation += 1
        return generation
    }

    /// The running fetch finished. Returns whether its result is current
    /// (nothing newer was asked meanwhile) and the generation to start next,
    /// if another fetch was asked for meanwhile.
    public mutating func finished(_ finishedGeneration: Int) -> (useResult: Bool, next: Int?) {
        guard finishedGeneration == generation else { return (false, nil) }
        running = false
        guard again else { return (true, nil) }
        again = false
        // Show this result now; the next fetch replaces it shortly.
        return (true, request())
    }

    /// Forget a running fetch (the widget was turned off): its result is dropped.
    public mutating func cancel() {
        running = false
        again = false
        generation += 1
    }
}
