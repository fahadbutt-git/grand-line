import Foundation

/// A provider that searches a catalog. Most providers are one of these, built by
/// a factory that knows how to load their rows (apps, menu entries, snippets…).
public final class CatalogProvider: InstantProvider, @unchecked Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let prefix: Prefix?
    public let inGlobalSearch: Bool
    public let catalog: Catalog
    /// Rows a global search keeps from this provider before ranking.
    let globalLimit: Int
    let loader: (@Sendable () -> [LaunchResult])?

    public init(
        id: String,
        title: String,
        symbol: String,
        prefix: Prefix? = nil,
        inGlobalSearch: Bool = true,
        globalLimit: Int = 40,
        stripsExtensions: Bool = false,
        loader: (@Sendable () -> [LaunchResult])? = nil
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.prefix = prefix
        self.inGlobalSearch = inGlobalSearch
        self.globalLimit = globalLimit
        self.catalog = Catalog(stripsExtensions: stripsExtensions)
        self.loader = loader
    }

    /// Reads the rows again from the source.
    public func reload() {
        guard let loader else { return }
        catalog.replace(loader().map { var r = $0; r.providerID = id; return r })
    }

    public func replace(_ results: [LaunchResult]) {
        catalog.replace(results.map { var r = $0; r.providerID = id; return r })
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let own = query.prefix != nil && query.prefix == prefix
        if query.term.isEmpty && !own { return [] }
        return catalog.search(query.term, exactOnly: query.prefix == .exact, limit: own ? 500 : globalLimit)
    }
}
