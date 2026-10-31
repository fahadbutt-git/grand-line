import FileKit
import Foundation
import IndexKit
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
    /// The plain words of the query (not text:, name: or other filters), which
    /// Spotlight matches by name or by content.
    public let words: [String]
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
            predicate: compiled.predicate, scopes: scopes, nameText: nameWords(parsed), words: plainWords(parsed),
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

    /// Whether a Spotlight result matched by its name: its name holds every plain
    /// word. False means it was found only by what is inside it.
    public func matchesName(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Whether a result may show at all, however it was found (the name index,
    /// the index service or Spotlight, by name or by content): not app data.
    /// That is ~/Library (except Google Drive), hidden folders, the insides of
    /// apps and other packages, .git, node_modules and caches, unless the search
    /// was limited to a folder inside such a place. Only the part of the path
    /// below the search's folder, or below the home folder, counts.
    public func keeps(_ path: String) -> Bool {
        let roots = (scopes + [home]).filter { $0.hasPrefix("/") && Backstage.isInside(path, $0) }
        let base = roots.max { $0.count < $1.count }
        return !Backstage.contains(path, home: home, scope: base, hidden: true)
    }

    /// Whether to show a result found only by its contents (see `keeps`).
    public func keepsContentMatch(_ path: String) -> Bool { keeps(path) }

    /// The scope's folders that the name index leaves out (the Trash, a
    /// node_modules, ~/Library), so their names are read from disk instead.
    public var foldersTheIndexSkips: [String] {
        scopes.filter { $0.hasPrefix("/") && Self.indexSkips($0, home: home) }
    }

    static func indexSkips(_ folder: String, home: String) -> Bool {
        var base = home
        while base.count > 1, base.hasSuffix("/") { base.removeLast() }
        guard Backstage.isInside(folder, base) else { return false }
        let names = folder.dropFirst(base.count).split(separator: "/").map(String.init)
        if names.first == "Library", names.dropFirst().first.map({ IndexExclusions.keptInLibrary.contains($0) }) != true {
            return true
        }
        let rules = IndexExclusions.standard
        return names.contains { rules.skips($0) || rules.isPackage($0) }
    }

    static func plainWords(_ query: ParsedQuery) -> [String] {
        guard let root = query.root else { return [] }
        let parts: [Node]
        if case .and(let children) = root { parts = children } else { parts = [root] }
        return parts.compactMap { part in
            if case .term(.text(let pattern)) = part { return pattern.text }
            return nil
        }
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
