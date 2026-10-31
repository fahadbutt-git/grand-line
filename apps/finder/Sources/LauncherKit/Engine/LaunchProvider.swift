import Foundation

/// A source of results. `results(for:)` is called once per keystroke inside a
/// task that is cancelled when the next key arrives, so long work should check
/// `Task.checkCancellation()` or stop its process on cancellation.
public protocol LaunchProvider: Sendable {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }
    /// The prefix that runs this provider alone, if any.
    var prefix: Prefix? { get }
    /// A first word that runs this provider alone ("zot glaucoma"), if any.
    var keyword: String? { get }
    /// Whether it runs for an unprefixed query.
    var inGlobalSearch: Bool { get }
    /// Whether it answers queries that are paths (~/ or /…).
    var handlesPaths: Bool { get }

    func results(for query: LaunchQuery) async throws -> [LaunchResult]
}

/// A provider fast enough to answer on the keystroke itself, with no waiting.
/// Its results are shown first; slower providers append below them.
public protocol InstantProvider: LaunchProvider {
    func instantResults(for query: LaunchQuery) -> [LaunchResult]
}

public extension LaunchProvider {
    var keyword: String? { nil }
    var handlesPaths: Bool { false }
}

public extension InstantProvider {
    func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        instantResults(for: query)
    }
}
