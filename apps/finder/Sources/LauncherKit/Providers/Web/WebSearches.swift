import Foundation

/// A search engine or quicklink: a keyword and a URL with %s for the query.
public struct WebSearch: Sendable, Equatable {
    public let keyword: String
    public let title: String
    public let template: String
    public let symbol: String

    public init(keyword: String, title: String, template: String, symbol: String = "globe") {
        self.keyword = keyword.lowercased()
        self.title = title
        self.template = template
        self.symbol = symbol
    }

    /// The template with the query encoded in place of %s.
    public func url(for query: String) -> String {
        template.replacingOccurrences(of: "%s", with: WebSearches.encode(query))
    }
}

public enum WebSearches {
    public static let builtIn: [WebSearch] = [
        WebSearch(keyword: "g", title: "Google", template: "https://www.google.com/search?q=%s", symbol: "magnifyingglass"),
        WebSearch(keyword: "pm", title: "PubMed", template: "https://pubmed.ncbi.nlm.nih.gov/?term=%s", symbol: "cross.case"),
        WebSearch(keyword: "gs", title: "Google Scholar", template: "https://scholar.google.com/scholar?q=%s", symbol: "graduationcap"),
        WebSearch(keyword: "yt", title: "YouTube", template: "https://www.youtube.com/results?search_query=%s", symbol: "play.rectangle"),
        WebSearch(keyword: "wiki", title: "Wikipedia", template: "https://en.wikipedia.org/wiki/Special:Search?search=%s", symbol: "book"),
    ]

    /// The built-in engines, then quicklinks.tsv (keyword TAB title TAB url with %s).
    /// A quicklink with a built-in keyword replaces it.
    public static func all(quicklinks text: String) -> [WebSearch] {
        var list = builtIn
        for row in TSV.rows(text) where row.count >= 3 && !row[0].isEmpty && !row[2].isEmpty {
            let search = WebSearch(keyword: row[0], title: row[1].isEmpty ? row[0] : row[1], template: row[2])
            list.removeAll { $0.keyword == search.keyword }
            list.append(search)
        }
        return list
    }

    /// Encoded for a query string: spaces as %20, and & + = # ? escaped.
    public static func encode(_ text: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// "github.com/x" and "https://…" are addresses, not searches.
    public static func address(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return URL(string: trimmed) != nil ? trimmed : nil }
        let host = trimmed.split(separator: "/").first.map(String.init) ?? ""
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              !trimmed.hasPrefix("."), labels.allSatisfy({ !$0.isEmpty }) else { return nil }
        // "report.pdf" is a file name, not a site.
        let fileTypes: Set<String> = ["pdf", "docx", "doc", "xlsx", "pptx", "txt", "md", "png", "jpg", "jpeg", "csv", "zip", "app", "swift", "py", "sh", "json"]
        guard !fileTypes.contains(tld.lowercased()) else { return nil }
        return "https://" + trimmed
    }

    public static func result(_ search: WebSearch, query: String, match: MatchInfo = .answer, isFallback: Bool = false) -> LaunchResult {
        let url = search.url(for: query)
        return LaunchResult(
            id: "web:\(search.keyword)",
            title: "Search \(search.title) for “\(query)”",
            subtitle: search.keyword + " · " + (URL(string: url)?.host ?? ""),
            icon: .symbol(search.symbol),
            section: .web,
            aliases: [search.keyword],
            accessory: "Web",
            actions: [
                LaunchAction("Open", symbol: "globe", .openURL(url, bundleID: nil)),
                .copy(url, title: "Copy URL"),
            ],
            isFallback: isFallback,
            providerID: "web",
            match: match
        )
    }
}
