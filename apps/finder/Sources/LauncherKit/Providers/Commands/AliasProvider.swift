import Foundation

/// Aliases that point at a URL or a path become rows of their own: "drive" →
/// ~/Drive, "lab" → https://… . Aliases for result ids are ranked by the Ranker.
public final class AliasProvider: InstantProvider, @unchecked Sendable {
    public let id = "aliases"
    public let title = "Aliases"
    public let symbol = "link"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    let paths: GrandLinePaths
    private let lock = NSLock()
    private var table = AliasTable()

    public init(paths: GrandLinePaths = GrandLinePaths()) {
        self.paths = paths
    }

    public var aliases: AliasTable { lock.withLock { table } }

    public func set(_ table: AliasTable) {
        lock.withLock { self.table = table }
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let folded = TextFold.simple(query.term)
        guard !folded.isEmpty else { return [] }
        return aliases.standalone.compactMap { entry in
            let match: AliasMatch = entry.alias == folded ? .exact : entry.alias.hasPrefix(folded) ? .prefix : .none
            guard match != .none else { return nil }
            let isWeb = entry.target.contains("://")
            let target = isWeb ? entry.target : paths.expand(entry.target)
            return LaunchResult(
                id: "alias:" + entry.alias,
                title: entry.alias,
                subtitle: isWeb ? target : paths.abbreviate(target),
                icon: .symbol(isWeb ? "link" : "folder"),
                section: isWeb ? .web : .files,
                accessory: "Alias",
                actions: [
                    LaunchAction("Open", symbol: "arrow.up.forward", isWeb ? .openURL(target, bundleID: nil) : .open(target)),
                    .copy(target, title: isWeb ? "Copy URL" : "Copy path"),
                ],
                previewPath: isWeb ? nil : target,
                providerID: id,
                match: MatchInfo(alias: match)
            )
        }
    }
}
