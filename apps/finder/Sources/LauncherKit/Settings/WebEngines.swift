import Foundation

/// A search engine as Settings, Web lists it: a name, a URL with %s where
/// the words go, a keyword ("pm glaucoma"), and whether it is offered at the
/// bottom of every search.
public struct WebEngine: Sendable, Equatable, Identifiable {
    public var id: String { keyword.isEmpty ? name.lowercased() : keyword }
    public var name: String
    public var template: String
    public var keyword: String
    public var fallback: Bool

    public init(name: String, template: String, keyword: String, fallback: Bool = false) {
        self.name = name
        self.template = template
        self.keyword = keyword
        self.fallback = fallback
    }

    /// The URL starts with http:// or https:// and has %s for the words.
    public static func problem(name: String, template: String, keyword: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let url = template.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "Give the engine a name." }
        if !(url.lowercased().hasPrefix("https://") || url.lowercased().hasPrefix("http://")) { return "The URL starts with https://." }
        if !url.contains("%s") { return "Put %s in the URL where the search words go." }
        if URL(string: url.replacingOccurrences(of: "%s", with: "x")) == nil { return "That URL is not valid." }
        if keyword.contains(" ") { return "A keyword is one word." }
        return nil
    }

    public var isValid: Bool { Self.problem(name: name, template: template, keyword: keyword) == nil }

    /// As the web provider uses it.
    public var search: WebSearch {
        let builtIn = WebSearches.builtIn.first { $0.keyword == keyword.lowercased() }
        return WebSearch(keyword: keyword, title: name, template: template, symbol: builtIn?.symbol ?? "globe")
    }
}

/// The engine list in Sight's defaults (`WebEngines`, a list of dictionaries
/// with name, url, keyword and fallback). Without it, the built-in engines,
/// with Google and PubMed as fallbacks, as before Settings existed.
public enum WebEngineList {
    public static let defaultsKey = "WebEngines"
    public static let assistantsKey = "AssistantFallbacks"
    public static let driveKey = "DriveFallback"

    public static var standard: [WebEngine] {
        WebSearches.builtIn.map {
            WebEngine(name: $0.title, template: $0.template, keyword: $0.keyword, fallback: $0.keyword == "g" || $0.keyword == "pm")
        }
    }

    /// Reads the stored list; entries that are not valid are skipped, and a
    /// missing or unreadable list gives the standard one. An empty list is kept.
    public static func parse(_ stored: Any?) -> [WebEngine] {
        guard let list = stored as? [Any] else { return standard }
        var engines: [WebEngine] = []
        var keywords = Set<String>()
        for case let entry as [String: Any] in list {
            let name = (entry["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let url = (entry["url"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let keyword = (entry["keyword"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            let fallback = (entry["fallback"] as? Bool) ?? ((entry["fallback"] as? NSNumber)?.boolValue ?? false)
            let engine = WebEngine(name: name, template: url, keyword: keyword, fallback: fallback)
            guard engine.isValid, keyword.isEmpty || keywords.insert(keyword).inserted else { continue }
            engines.append(engine)
        }
        return engines
    }

    public static func stored(_ engines: [WebEngine]) -> [[String: Any]] {
        engines.map { ["name": $0.name, "url": $0.template, "keyword": $0.keyword.lowercased(), "fallback": $0.fallback] }
    }

    /// The `?` list and keywords: the engines with a keyword, then quicklinks.tsv
    /// (a quicklink with the same keyword replaces the engine).
    public static func searches(_ engines: [WebEngine], quicklinks text: String) -> [WebSearch] {
        var list = engines.filter { !$0.keyword.isEmpty }.map(\.search)
        for row in TSV.rows(text) where row.count >= 3 && !row[0].isEmpty && !row[2].isEmpty {
            let search = WebSearch(keyword: row[0], title: row[1].isEmpty ? row[0] : row[1], template: row[2])
            list.removeAll { $0.keyword == search.keyword }
            list.append(search)
        }
        return list
    }

    /// What the bottom of every search offers.
    public struct Fallbacks: Sendable, Equatable {
        public var engines: [WebEngine]
        public var assistants: Bool
        public var drive: Bool

        public init(engines: [WebEngine] = WebEngineList.standard.filter(\.fallback), assistants: Bool = true, drive: Bool = true) {
            self.engines = engines
            self.assistants = assistants
            self.drive = drive
        }

        public static let standard = Fallbacks()
    }
}
