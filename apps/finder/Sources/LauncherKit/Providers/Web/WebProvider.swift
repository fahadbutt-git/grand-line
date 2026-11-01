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
    /// The engines from Settings, Web; quicklinks.tsv adds to them.
    private var engines = WebEngineList.standard
    /// Counts changes of `engines`, so a list built from older engines is not kept.
    private var enginesVersion = 0
    /// Called between building the list and keeping it (tests only).
    var afterBuild: (() -> Void)?

    public init(quicklinksFile: String = GrandLinePaths().quicklinks) {
        self.quicklinksFile = quicklinksFile
    }

    /// Reads quicklinks.tsv and builds the list. When Settings changed the
    /// engines while the list was being built, it is built again from the new
    /// ones rather than kept: a reload never puts back older engines.
    public func reload() {
        let text = (try? String(contentsOfFile: quicklinksFile, encoding: .utf8)) ?? ""
        while true {
            let (engines, version) = lock.withLock { (self.engines, enginesVersion) }
            let built = WebEngineList.searches(engines, quicklinks: text)
            afterBuild?()
            let kept = lock.withLock { () -> Bool in
                guard enginesVersion == version else { return false }
                searches = built
                return true
            }
            if kept { return }
        }
    }

    /// New engines from Settings take effect at once.
    public func setEngines(_ list: [WebEngine]) {
        lock.withLock {
            engines = list
            enginesVersion += 1
        }
        reload()
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
