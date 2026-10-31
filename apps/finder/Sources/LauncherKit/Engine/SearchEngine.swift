import Foundation

/// Runs a query through the providers it is meant for: instant providers on the
/// keystroke itself, then the others concurrently, each batch ranked as it lands.
public final class SearchEngine: Sendable {
    public let providers: [any LaunchProvider]
    public let router: PrefixRouter
    public let ranker: Ranker
    /// A prefix shows one provider, so its section may hold this many times more rows.
    static let prefixScale = 8

    public init(providers: [any LaunchProvider], router: PrefixRouter = PrefixRouter(), ranker: Ranker = Ranker()) {
        self.providers = providers
        self.router = router
        self.ranker = ranker
    }

    public struct Plan: Sendable {
        public let query: LaunchQuery
        public let providers: [any LaunchProvider]
        /// Whether the best row is lifted into Top hit.
        public let topHit: Bool
        public let limitScale: Int
    }

    /// Which providers a query goes to, and how its results are shown.
    public func plan(_ text: String) -> Plan {
        let query = router.parse(text)
        if query.isPath {
            return Plan(query: query, providers: providers.filter { $0.handlesPaths }, topHit: false, limitScale: Self.prefixScale)
        }
        if let prefix = query.prefix, prefix != .exact {
            return Plan(query: query, providers: providers.filter { $0.prefix == prefix }, topHit: false, limitScale: Self.prefixScale)
        }
        if query.prefix == nil, let split = query.keywordSplit,
           let owner = providers.first(where: { $0.keyword?.lowercased() == split.keyword }) {
            let inner = LaunchQuery(raw: query.raw, term: split.rest)
            return Plan(query: inner, providers: [owner], topHit: false, limitScale: Self.prefixScale)
        }
        return Plan(query: query, providers: providers.filter { $0.inGlobalSearch }, topHit: !query.isEmpty, limitScale: 1)
    }

    /// The instant providers' results, ranked and grouped, without waiting.
    public func instantGroups(_ plan: Plan) -> [ResultGroup] {
        var results: [LaunchResult] = []
        for case let provider as any InstantProvider in plan.providers {
            results += provider.instantResults(for: plan.query)
        }
        let ranked = ranker.rank(results, query: plan.query)
        return ResultGrouping.group(ranked, topHit: plan.topHit, limitScale: plan.limitScale)
    }

    /// Every update for one query. Cancelling the consuming task (or dropping the
    /// stream) cancels the providers still running.
    public func search(_ text: String) -> AsyncStream<SearchUpdate> {
        search(plan(text))
    }

    /// The window applies the instant groups itself on the keystroke, then reads
    /// only the slower providers' updates from here (`includeInstant: false`).
    public func search(_ plan: Plan, includeInstant: Bool = true) -> AsyncStream<SearchUpdate> {
        let ranker = self.ranker
        let started = Date()
        return AsyncStream { continuation in
            if includeInstant {
                continuation.yield(.replace(instantGroups(plan), limitScale: plan.limitScale))
            }
            let slow = plan.providers.filter { !($0 is any InstantProvider) }
            let task = Task {
                await withTaskGroup(of: [LaunchResult].self) { group in
                    for provider in slow {
                        group.addTask { (try? await provider.results(for: plan.query)) ?? [] }
                    }
                    for await batch in group where !batch.isEmpty {
                        if Task.isCancelled { break }
                        continuation.yield(.merge(ranker.rank(batch, query: plan.query)))
                    }
                }
                if !Task.isCancelled {
                    continuation.yield(.finished(milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
