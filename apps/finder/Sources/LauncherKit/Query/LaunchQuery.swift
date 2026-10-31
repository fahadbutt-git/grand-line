import Foundation

/// A typed query after the prefix router has read it.
public struct LaunchQuery: Sendable, Equatable {
    /// Exactly what was typed.
    public let raw: String
    public let prefix: Prefix?
    /// The text after the prefix, trimmed.
    public let term: String
    /// Text starting with ~/ or / that names a path.
    public let isPath: Bool

    public init(raw: String, prefix: Prefix? = nil, term: String? = nil, isPath: Bool = false) {
        self.raw = raw
        self.prefix = prefix
        self.term = term ?? raw.trimmingCharacters(in: .whitespaces)
        self.isPath = isPath
    }

    public var isEmpty: Bool { term.isEmpty }

    /// The first word of the term, lowercased, and the rest, for keywords such as "pm glaucoma".
    public var keywordSplit: (keyword: String, rest: String)? {
        guard let space = term.firstIndex(of: " ") else { return nil }
        let rest = term[term.index(after: space)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (term[..<space].lowercased(), rest)
    }

    /// The key learned rankings are stored under: the prefix and the folded term.
    public var usageKey: String {
        (prefix?.rawValue ?? "") + TextFold.simple(term)
    }
}
