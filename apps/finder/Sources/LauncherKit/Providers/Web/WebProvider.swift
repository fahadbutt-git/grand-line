import Foundation

/// The `?` prefix lists every engine for the query ("?pm glaucoma" picks one).
/// Without a prefix, "pm glaucoma" puts PubMed on top, and an address opens.
public final class WebProvider: InstantProvider, @unchecked Sendable {
    public let id = "web"
    public let title = "Web search"
    public let symbol = "globe"
    public let prefix: Prefix? = .web
    public let inGlobalSearch = true
    let quicklinksFile: String
    private let lock = NSLock()
    private var searches = WebSearches.builtIn

    public init(quicklinksFile: String = GrandLinePaths().quicklinks) {
        self.quicklinksFile = quicklinksFile
    }

    public func reload() {
        let text = (try? String(contentsOfFile: quicklinksFile, encoding: .utf8)) ?? ""
        set(WebSearches.all(quicklinks: text))
    }

    public func set(_ list: [WebSearch]) {
        lock.withLock { searches = list }
    }

    var current: [WebSearch] { lock.withLock { searches } }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard !query.term.isEmpty else { return [] }
        let all = current
        var rows: [LaunchResult] = []
        if let address = WebSearches.address(query.term) {
            rows.append(LaunchResult(
                id: "url:" + address,
                title: "Open \(query.term)",
                subtitle: address,
                icon: .symbol("safari"),
                section: .web,
                accessory: "Web",
                actions: [LaunchAction("Open", symbol: "safari", .openURL(address, bundleID: nil)), .copy(address, title: "Copy URL")],
                providerID: id,
                match: MatchInfo(title: .prefix)
            ))
        }
        if let split = query.keywordSplit, let search = all.first(where: { $0.keyword == split.keyword }) {
            rows.append(WebSearches.result(search, query: split.rest, match: MatchInfo(alias: .exact, title: .exact)))
        } else if query.prefix == .web {
            rows += all.map { WebSearches.result($0, query: query.term) }
        }
        return rows
    }
}
