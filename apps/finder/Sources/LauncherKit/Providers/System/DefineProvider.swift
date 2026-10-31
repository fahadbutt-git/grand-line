import Foundation

/// "define glaucoma" and "syn happy": the definition from macOS's dictionaries.
/// The lookup is injected; the app uses Dictionary Services.
public struct DefineProvider: LaunchProvider {
    public let id = "define"
    public let title = "Dictionary"
    public let symbol = "character.book.closed"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    let lookup: @Sendable (String) -> String?

    public init(lookup: @escaping @Sendable (String) -> String?) {
        self.lookup = lookup
    }

    public enum Kind: Sendable, Equatable { case define, synonyms }

    public static func parse(_ term: String) -> (word: String, kind: Kind)? {
        let lower = term.lowercased()
        let leads: [(String, Kind)] = [("define ", .define), ("def ", .define), ("synonyms ", .synonyms), ("syn ", .synonyms)]
        for (lead, kind) in leads where lower.hasPrefix(lead) {
            let word = String(term.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { return nil }
            return (word: word, kind: kind)
        }
        return nil
    }

    /// The first sentence of a definition, for the row; the whole text goes to the preview.
    public static func summary(_ text: String, limit: Int = 160) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if let end = flat.range(of: ". "), flat.distance(from: flat.startIndex, to: end.lowerBound) < limit {
            return String(flat[..<end.lowerBound]) + "."
        }
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// The part of a thesaurus entry after "synonyms"/"THESAURUS", when the dictionary text has one.
    public static func synonyms(_ text: String) -> String? {
        for marker in ["THESAURUS", "synonyms:", "Synonyms"] {
            if let range = text.range(of: marker) {
                let rest = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !rest.isEmpty { return summary(String(rest)) }
            }
        }
        return nil
    }

    public func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        guard query.prefix == nil, let request = Self.parse(query.term), let text = lookup(request.word) else { return [] }
        try Task.checkCancellation()
        let line = request.kind == .synonyms ? (Self.synonyms(text) ?? Self.summary(text)) : Self.summary(text)
        return [LaunchResult(
            id: "define:" + request.word.lowercased(),
            title: line,
            subtitle: (request.kind == .synonyms ? "Synonyms for " : "Definition of ") + request.word,
            icon: .symbol("character.book.closed"),
            section: .answers,
            actions: [
                LaunchAction("Open in Dictionary", symbol: "book", .lookUp(request.word)),
                .copy(text, title: "Copy definition"),
            ],
            detail: text,
            providerID: id,
            match: .answer
        )]
    }
}
