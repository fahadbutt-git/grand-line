import Foundation

/// The empty query: favourites first, then what you ran most recently.
public struct RecentsProvider: InstantProvider {
    public let id = "recents"
    public let title = "Recents"
    public let symbol = "clock"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    let usage: UsageStore

    public init(usage: UsageStore) {
        self.usage = usage
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard query.term.isEmpty, query.prefix == nil else { return [] }
        let favourites = usage.favourites().map { row -> LaunchResult in
            var r = row
            r.section = .favourites
            r.match = .answer
            return r
        }
        let recents = usage.recents(limit: 9).map { row -> LaunchResult in
            var r = row
            r.section = .recents
            r.match = MatchInfo(title: .prefix)
            return r
        }
        return favourites + recents
    }
}
