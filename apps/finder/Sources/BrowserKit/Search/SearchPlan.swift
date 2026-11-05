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
    /// Spotlight matches by name or by content. Saved searches (`@name`) are
    /// expanded first, so their words count too.
    public let words: [String]
    /// Whether Spotlight may match files by what is inside them: a plain word
    /// with content matches on, or `text:`.
    public let searchesContent: Bool
    /// Nothing in the query narrows the results (an empty or unknown `@name`,
    /// a filter still being typed). Such a search runs nothing and shows
    /// nothing, rather than every file in the scope.
    public let isUnconstrained: Bool
    /// The query with saved searches expanded.
    let expanded: Node?
    let postFilter: @Sendable (String) -> Bool
    let home: String
    let drives: [GoogleDrive]

    /// - Parameter content: whether plain words also match inside files
    ///   (Settings, Search, "Include content matches", and the search's own
    ///   "inside files" toggle). `text:` always does.
    public static func make(
        _ text: String, scope: SearchScope, home: String, drives: [GoogleDrive],
        savedSearch: (String) -> String? = { _ in nil }, now: Date = Date(), content: Bool = true
    ) -> SearchPlan {
        let parsed = QueryParser.parse(text)
        let expanded = SpotlightCompiler.expanded(parsed, savedSearch: savedSearch)
        let compiled = SpotlightCompiler.compile(parsed, now: now, home: home, savedSearch: savedSearch, content: content)
        let scopes = compiled.scopes.isEmpty ? scope.spotlightScopes(home: home, drives: drives) : compiled.scopes
        return SearchPlan(
            text: text, scope: scope, parsed: parsed, chips: QueryChips.describe(parsed),
            predicate: compiled.predicate, scopes: scopes, nameText: nameWords(expanded), words: plainWords(expanded),
            searchesContent: compiled.searchesContent, isUnconstrained: compiled.isUnconstrained, expanded: expanded.root,
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

    /// Whether a Spotlight result matched by its name: the query holds for the
    /// name alone, its words found in the name (a filter such as kind: or
    /// modified: already holds, since Spotlight returned it). False means it
    /// was found only by what is inside it. A query that never looks inside
    /// files matches everything by name or by its filters.
    public func matchesName(_ path: String) -> Bool {
        guard searchesContent, let expanded else { return true }
        return Self.nameHolds(expanded, (path as NSString).lastPathComponent)
    }

    static func nameHolds(_ node: Node, _ name: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        func holds(_ pattern: Pattern) -> Bool {
            if pattern.style == .prefix { return name.range(of: pattern.text, options: options.union(.anchored)) != nil }
            return name.range(of: pattern.text, options: options) != nil
        }
        switch node {
        case .term(.text(let pattern)), .term(.field(.name, let pattern)): return holds(pattern)
        case .term(.field(.content, _)): return false
        case .term: return true
        case .and(let children): return children.allSatisfy { nameHolds($0, name) }
        case .or(let children): return children.contains { nameHolds($0, name) }
        // An exclusion already held for the file as Spotlight found it.
        case .not, .saved: return true
        }
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
        query.root.map { plainWords($0) } ?? []
    }

    static func plainWords(_ root: Node) -> [String] {
        conjuncts(root).compactMap { part in
            if case .term(.text(let pattern)) = part { return pattern.text }
            return nil
        }
    }

    static func nameWords(_ query: ParsedQuery) -> String? {
        query.root.flatMap { nameWords($0) }
    }

    static func nameWords(_ root: Node) -> String? {
        var words: [String] = []
        for part in conjuncts(root) {
            switch part {
            case .term(.text(let pattern)), .term(.field(.name, let pattern)):
                words.append(pattern.text)
            default:
                return nil
            }
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// The parts ANDed together, a saved search's own ANDs included.
    static func conjuncts(_ node: Node) -> [Node] {
        guard case .and(let children) = node else { return [node] }
        return children.flatMap { conjuncts($0) }
    }
}
