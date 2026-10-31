import Foundation

/// The rows at the bottom of every search: Drive content, Google, PubMed, and
/// the assistants. They never become the top hit.
public struct FallbackProvider: InstantProvider {
    public let id = "fallbacks"
    public let title = "Fallbacks"
    public let symbol = "arrow.turn.down.right"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true

    public init() {}

    static let assistants: [(name: String, template: String, symbol: String)] = [
        ("Claude", "https://claude.ai/new?q=%s", "sparkle"),
        ("ChatGPT", "https://chatgpt.com/?q=%s", "bubble.left.and.text.bubble.right"),
        ("Gemini", "https://gemini.google.com/app?q=%s", "sparkles"),
    ]

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let term = query.term
        guard !term.isEmpty, query.prefix == nil || query.prefix == .exact else { return [] }
        var rows: [LaunchResult] = [LaunchResult(
            id: "fallback:drive",
            title: "Search Drive contents for “\(term)”",
            subtitle: "Files whose text matches, in Google Drive",
            icon: .symbol("doc.text.magnifyingglass"),
            section: .web,
            accessory: "Files",
            actions: [LaunchAction.complete(". \(term) drive:", title: "Search")],
            isFallback: true,
            providerID: id
        )]
        for search in WebSearches.builtIn where search.keyword == "g" || search.keyword == "pm" {
            var row = WebSearches.result(search, query: term, match: .unmatched, isFallback: true)
            row.id = "fallback:" + search.keyword
            rows.append(row)
        }
        for assistant in Self.assistants {
            let url = assistant.template.replacingOccurrences(of: "%s", with: WebSearches.encode(term))
            rows.append(LaunchResult(
                id: "fallback:" + assistant.name.lowercased(),
                title: "Ask \(assistant.name) “\(term)”",
                subtitle: URL(string: url)?.host ?? "",
                icon: .symbol(assistant.symbol),
                section: .web,
                accessory: "Ask",
                actions: [
                    LaunchAction("Open", symbol: "globe", .openURL(url, bundleID: nil)),
                    LaunchAction.copy(term, title: "Copy question"),
                ],
                isFallback: true,
                providerID: id
            ))
        }
        return rows
    }
}
