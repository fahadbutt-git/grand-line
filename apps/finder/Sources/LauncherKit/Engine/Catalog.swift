import Foundation
import IndexKit

/// A list of results folded once for matching, swapped whole when its source
/// changes. Searching it is synchronous and safe from any thread.
public final class Catalog: @unchecked Sendable {
    struct Item {
        let result: LaunchResult
        let title: FoldedText
        let keywords: [FoldedText]
    }

    private let lock = NSLock()
    private var items: [Item] = []
    let stripsExtensions: Bool

    public init(_ results: [LaunchResult] = [], stripsExtensions: Bool = false) {
        self.stripsExtensions = stripsExtensions
        replace(results)
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    public func replace(_ results: [LaunchResult]) {
        let strips = stripsExtensions
        let folded = results.map {
            Item(result: $0, title: FoldedText($0.title, stripsExtension: strips), keywords: $0.keywords.map { FoldedText($0) })
        }
        lock.lock()
        items = folded
        lock.unlock()
    }

    /// Rows that match `term` by title, keyword or own alias, each with its match
    /// filled in. An empty term returns everything, unmatched, up to `limit`.
    public func search(_ term: String, exactOnly: Bool = false, limit: Int = .max) -> [LaunchResult] {
        lock.lock()
        let items = self.items
        lock.unlock()
        let matcher = TextMatcher(term, exactOnly: exactOnly)
        guard !matcher.isEmpty else { return Array(items.prefix(limit).map(\.result)) }
        let folded = TextFold.simple(term)
        var found: [LaunchResult] = []
        for item in items {
            var match = MatchInfo()
            if let hit = matcher.match(item.title) {
                match.title = hit.tier
                match.quality = hit.quality
                match.highlights = matcher.highlights(hit, in: item.title)
            } else if let hit = matcher.bestMatch(item.keywords) {
                match.keyword = hit.tier
                match.quality = hit.quality
            }
            for alias in item.result.aliases where !folded.isEmpty {
                if alias == folded { match.alias = .exact } else if match.alias == .none, alias.hasPrefix(folded) { match.alias = .prefix }
            }
            guard match.matched else { continue }
            var result = item.result
            result.match = match
            found.append(result)
        }
        if found.count > limit {
            found.sort { ($0.match.alias, $0.match.title?.rawValue ?? 5, $0.match.keyword?.rawValue ?? 5) < ($1.match.alias, $1.match.title?.rawValue ?? 5, $1.match.keyword?.rawValue ?? 5) }
            found.removeLast(found.count - limit)
        }
        return found
    }
}
