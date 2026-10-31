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
    /// Other prefixes it also answers ("," for the settings rows, ">" for commands).
    var extraPrefixes: [Prefix] { get }
    /// A first word that runs this provider alone ("zot glaucoma"), if any.
    var keyword: String? { get }
    /// Whether the keyword and a space alone ("zot ") already run it, with an empty term.
    var routesBareKeyword: Bool { get }
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
    var routesBareKeyword: Bool { false }
    var handlesPaths: Bool { false }
    var extraPrefixes: [Prefix] { [] }

    /// Whether a query with this prefix goes to this provider.
    func serves(_ prefix: Prefix) -> Bool {
        self.prefix == prefix || extraPrefixes.contains(prefix)
    }
}

/// A provider whose rows only appear when nothing else matched: create a
/// file with that name, run it in Terminal, calculate it.
public protocol NoMatchProvider: LaunchProvider {
    func noMatchResults(for query: LaunchQuery) -> [LaunchResult]
}

public extension InstantProvider {
    func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        instantResults(for: query)
    }
}
