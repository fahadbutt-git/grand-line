import FileKit
import Foundation
import QueryKit

/// One search as typed (R2, R3): QueryKit's parse, chips and Spotlight query,
/// the scope's roots, and the plain words IndexKit can match by name at once.
public struct SearchPlan {
    public let text: String
    public let scope: SearchScope
    public let parsed: ParsedQuery
    /// "Word or PDF", "changed in the last 30 days".
    public let chips: [String]
    public let predicate: NSPredicate
    /// The query's own folders when it names any, else the scope's roots.
    public let scopes: [String]
    /// Words for IndexKit, when the query is only names and words; nil otherwise.
    public let nameText: String?
    let postFilter: @Sendable (String) -> Bool
    let home: String
    let drives: [GoogleDrive]

    public static func make(
        _ text: String, scope: SearchScope, home: String, drives: [GoogleDrive],
        savedSearch: (String) -> String? = { _ in nil }, now: Date = Date()
    ) -> SearchPlan {
        let parsed = QueryParser.parse(text)
        let compiled = SpotlightCompiler.compile(parsed, now: now, home: home, savedSearch: savedSearch)
        let scopes = compiled.scopes.isEmpty ? scope.spotlightScopes(home: home, drives: drives) : compiled.scopes
        return SearchPlan(
            text: text, scope: scope, parsed: parsed, chips: QueryChips.describe(parsed),
            predicate: compiled.predicate, scopes: scopes, nameText: nameWords(parsed),
            postFilter: compiled.postFilter, home: home, drives: drives
        )
    }

    public var hasIssues: Bool { !parsed.issues.isEmpty }

    /// Whether a result belongs: inside the scope and passing the query's folder rules.
    public func accepts(_ path: String) -> Bool {
        let inScope = scopes != scope.spotlightScopes(home: home, drives: drives)
            || scope.contains(path, home: home, drives: drives)
        return inScope && postFilter(path)
    }

    static func nameWords(_ query: ParsedQuery) -> String? {
        guard let root = query.root else { return nil }
        let parts: [Node]
        if case .and(let children) = root { parts = children } else { parts = [root] }
        var words: [String] = []
        for part in parts {
            switch part {
            case .term(.text(let pattern)), .term(.field(.name, let pattern)):
                words.append(pattern.text)
            default:
                return nil
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}
