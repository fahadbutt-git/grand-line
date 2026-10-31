import Foundation

public struct SpotlightQuery {
    public let predicate: NSPredicate
    /// Search roots for NSMetadataQuery.searchScopes. Empty means the caller's default scope.
    public let scopes: [String]
    /// Applied to each result's path, for folder rules Spotlight cannot query.
    public let postFilter: @Sendable (String) -> Bool
    public let sort: SortKey?
}

public enum SpotlightCompiler {
    public static func compile(
        _ query: ParsedQuery,
        now: Date = .now,
        calendar: Calendar = .current,
        home: String = NSHomeDirectory(),
        savedSearch: (String) -> String? = { _ in nil }
    ) -> SpotlightQuery {
        var sort = query.sort
        var root: Node?
        if let original = query.root {
            root = expand(original, savedSearch, visiting: [], sort: &sort)
        }

        let builder = PredicateBuilder(now: now, calendar: calendar, home: home)
        var predicates: [NSPredicate] = []
        var tests: [@Sendable (String) -> Bool] = []
        var scopes: [String] = []
        for conjunct in root.map(conjuncts) ?? [] {
            if conjunct.isPathOnly {
                tests.append(builder.pathTest(conjunct))
                scopes += builder.scopeRoots(conjunct) ?? []
            } else if let predicate = builder.predicate(conjunct) {
                predicates.append(predicate)
            }
        }

        var seen = Set<String>()
        let uniqueScopes = scopes.filter { seen.insert($0).inserted }
        let finalTests = tests
        return SpotlightQuery(
            predicate: PredicateBuilder.allOf(predicates) ?? PredicateBuilder.matchAll,
            scopes: uniqueScopes,
            postFilter: { path in finalTests.allSatisfy { $0(path) } },
            sort: sort
        )
    }

    static func conjuncts(_ node: Node) -> [Node] {
        guard case .and(let children) = node else { return [node] }
        var result: [Node] = []
        for child in children { result += conjuncts(child) }
        return result
    }

    static func expand(_ node: Node, _ lookup: (String) -> String?, visiting: Set<String>, sort: inout SortKey?) -> Node? {
        switch node {
        case .term:
            return node
        case .saved(let name):
            let key = name.lowercased()
            guard !visiting.contains(key), let text = lookup(name) else { return nil }
            let parsed = QueryParser.parse(text)
            if sort == nil { sort = parsed.sort }
            guard let inner = parsed.root else { return nil }
            return expand(inner, lookup, visiting: visiting.union([key]), sort: &sort)
        case .not(let inner):
            guard let expanded = expand(inner, lookup, visiting: visiting, sort: &sort) else { return nil }
            return .not(expanded)
        case .and(let children), .or(let children):
            var expanded: [Node] = []
            for child in children {
                if let result = expand(child, lookup, visiting: visiting, sort: &sort) {
                    expanded.append(result)
                }
            }
            if expanded.count <= 1 { return expanded.first }
            if case .and = node { return .and(expanded) }
            return .or(expanded)
        }
    }
}

struct PredicateBuilder {
    let now: Date
    let calendar: Calendar
    let home: String

    static let nameKey = "kMDItemFSName"
    static let contentKey = "kMDItemTextContent"

    static var matchAll: NSPredicate {
        compare(nameKey, .equalTo, "*")
    }

    // MARK: Predicates

    /// Returns nil when the node places no constraint on metadata.
    func predicate(_ node: Node) -> NSPredicate? {
        switch node {
        case .term(let term):
            return predicate(term)
        case .and(let children):
            var parts: [NSPredicate] = []
            for child in children {
                if let part = predicate(child) { parts.append(part) }
            }
            return PredicateBuilder.allOf(parts)
        case .or(let children):
            var parts: [NSPredicate] = []
            for child in children {
                guard let part = predicate(child) else { return nil }
                parts.append(part)
            }
            return PredicateBuilder.oneOf(parts)
        case .not(let inner):
            return predicate(inner).map { NSCompoundPredicate(notPredicateWithSubpredicate: $0) }
        case .saved:
            return nil
        }
    }

    private func predicate(_ term: Term) -> NSPredicate? {
        typealias B = PredicateBuilder
        switch term {
        case .text(let pattern):
            return B.oneOf([nameMatch(pattern), B.contains(B.contentKey, pattern.text)])
        case .field(let field, let pattern):
            return fieldMatch(field, pattern)
        case .kind(let kind):
            return B.oneOf(kind.contentTypes.map { B.compare("kMDItemContentTypeTree", .equalTo, $0) })
        case .folder, .location:
            return nil
        case .date(let field, let comparison):
            return datePredicate(field.attribute, comparison)
        case .size(let comparison):
            return B.number("kMDItemFSSize", comparison)
        case .pages(let comparison):
            return B.number("kMDItemNumberOfPages", comparison)
        }
    }

    private func nameMatch(_ pattern: Pattern) -> NSPredicate {
        if pattern.style == .prefix {
            return PredicateBuilder.wildcard(PredicateBuilder.nameKey, PredicateBuilder.literal(pattern.text) + "*")
        }
        return PredicateBuilder.contains(PredicateBuilder.nameKey, pattern.text)
    }

    private func fieldMatch(_ field: TextField, _ pattern: Pattern) -> NSPredicate {
        typealias B = PredicateBuilder
        switch field {
        case .name:
            return nameMatch(pattern)
        case .content:
            return B.contains(B.contentKey, pattern.text)
        case .ext:
            let ext = pattern.text.hasPrefix(".") ? pattern.text : "." + pattern.text
            return B.compare(B.nameKey, .endsWith, ext, options: B.insensitive)
        case .from:
            return B.contains("kMDItemWhereFroms", pattern.text)
        case .tag:
            let tag = B.literal(pattern.text)
            return B.wildcard("kMDItemUserTags", pattern.style == .prefix ? tag + "*" : tag)
        case .author:
            return B.contains("kMDItemAuthors", pattern.text)
        }
    }

    private func datePredicate(_ key: String, _ comparison: Comparison<DateSpec>) -> NSPredicate? {
        typealias B = PredicateBuilder
        func atLeast(_ date: Date) -> NSPredicate { B.compare(key, .greaterThanOrEqualTo, date) }
        func before(_ date: Date) -> NSPredicate { B.compare(key, .lessThan, date) }

        if case .between(let a, let b) = comparison {
            guard let first = interval(a), let second = interval(b) else { return nil }
            return B.allOf([atLeast(min(first.start, second.start)), before(max(first.end, second.end))])
        }
        let spec: DateSpec
        switch comparison {
        case .equal(let s), .less(let s), .lessOrEqual(let s), .greater(let s), .greaterOrEqual(let s):
            spec = s
        case .between:
            return nil
        }
        guard let range = interval(spec) else { return nil }
        if spec.isRelative {
            switch comparison {
            case .greater, .greaterOrEqual: return before(range.start)
            default: return atLeast(range.start)
            }
        }
        switch comparison {
        case .equal: return B.allOf([atLeast(range.start), before(range.end)])
        case .less: return before(range.start)
        case .lessOrEqual: return before(range.end)
        case .greater: return atLeast(range.end)
        case .greaterOrEqual: return atLeast(range.start)
        case .between: return nil
        }
    }

    /// The span a date value covers; a relative value is a single point.
    func interval(_ spec: DateSpec) -> (start: Date, end: Date)? {
        func span(_ components: DateComponents, _ unit: Calendar.Component) -> (start: Date, end: Date)? {
            guard let start = calendar.date(from: components),
                  let end = calendar.date(byAdding: unit, value: 1, to: start) else { return nil }
            return (start, end)
        }
        switch spec {
        case .today:
            let start = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return (start, end)
        case .yesterday:
            let end = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -1, to: end) else { return nil }
            return (start, end)
        case .daysAgo(let days):
            guard let point = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }
            return (point, point)
        case .year(let year):
            return span(DateComponents(year: year, month: 1, day: 1), .year)
        case .month(let year, let month):
            return span(DateComponents(year: year, month: month, day: 1), .month)
        case .day(let year, let month, let day):
            return span(DateComponents(year: year, month: month, day: day), .day)
        }
    }

    // MARK: Folders

    func absolutePath(_ folder: String) -> String? {
        var path: String
        if folder == "~" {
            path = home
        } else if folder.hasPrefix("~/") {
            path = home + String(folder.dropFirst())
        } else if folder.hasPrefix("/") {
            path = folder
        } else {
            return nil
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    func pathTest(_ node: Node) -> @Sendable (String) -> Bool {
        switch node {
        case .term(.folder(let folder)):
            if let root = absolutePath(folder) {
                let exact = root.lowercased()
                let prefix = exact == "/" ? "/" : exact + "/"
                return { path in
                    let lowered = path.lowercased()
                    return lowered == exact || lowered.hasPrefix(prefix)
                }
            }
            var name = Substring(folder)
            while name.hasSuffix("/") { name = name.dropLast() }
            let needle = "/" + String(name) + "/"
            return { path in path.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        case .term(.location(.googleDrive)):
            let base = (home + "/Library/CloudStorage/GoogleDrive-").lowercased()
            return { path in path.lowercased().hasPrefix(base) }
        case .term(.location(.local)):
            let inside = home.lowercased() + "/"
            let cloud = (home + "/Library/CloudStorage/").lowercased()
            return { path in
                let lowered = path.lowercased()
                return lowered.hasPrefix(inside) && !lowered.hasPrefix(cloud)
            }
        case .and(let children):
            let tests = children.map { pathTest($0) }
            return { path in tests.allSatisfy { $0(path) } }
        case .or(let children):
            let tests = children.map { pathTest($0) }
            return { path in tests.contains { $0(path) } }
        case .not(let inner):
            let test = pathTest(inner)
            return { path in !test(path) }
        case .term, .saved:
            return { _ in true }
        }
    }

    func scopeRoots(_ node: Node) -> [String]? {
        switch node {
        case .term(.folder(let folder)):
            return absolutePath(folder).map { [$0] }
        case .term(.location(.googleDrive)):
            return [home + "/Library/CloudStorage"]
        case .term(.location(.local)):
            return [home]
        case .or(let children):
            var roots: [String] = []
            for child in children {
                guard let childRoots = scopeRoots(child) else { return nil }
                roots += childRoots
            }
            return roots
        default:
            return nil
        }
    }

    // MARK: Primitives

    static var insensitive: NSComparisonPredicate.Options {
        [.caseInsensitive, .diacriticInsensitive]
    }

    static func compare(
        _ key: String,
        _ type: NSComparisonPredicate.Operator,
        _ value: Any,
        options: NSComparisonPredicate.Options = []
    ) -> NSPredicate {
        NSComparisonPredicate(
            leftExpression: NSExpression(forKeyPath: key),
            rightExpression: NSExpression(forConstantValue: value),
            modifier: .direct,
            type: type,
            options: options
        )
    }

    static func contains(_ key: String, _ text: String) -> NSPredicate {
        compare(key, .contains, text, options: insensitive)
    }

    /// Spotlight treats * and ? in an == comparison as wildcards.
    static func wildcard(_ key: String, _ pattern: String) -> NSPredicate {
        compare(key, .equalTo, pattern, options: insensitive)
    }

    /// Removes characters Spotlight would read as wildcards.
    static func literal(_ text: String) -> String {
        text.filter { $0 != "*" && $0 != "?" }
    }

    static func number(_ key: String, _ comparison: Comparison<Int64>) -> NSPredicate {
        func make(_ type: NSComparisonPredicate.Operator, _ value: Int64) -> NSPredicate {
            compare(key, type, NSNumber(value: value))
        }
        switch comparison {
        case .equal(let v): return make(.equalTo, v)
        case .less(let v): return make(.lessThan, v)
        case .lessOrEqual(let v): return make(.lessThanOrEqualTo, v)
        case .greater(let v): return make(.greaterThan, v)
        case .greaterOrEqual(let v): return make(.greaterThanOrEqualTo, v)
        case .between(let a, let b):
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                make(.greaterThanOrEqualTo, min(a, b)),
                make(.lessThanOrEqualTo, max(a, b)),
            ])
        }
    }

    static func allOf(_ parts: [NSPredicate]) -> NSPredicate? {
        parts.count <= 1 ? parts.first : NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    static func oneOf(_ parts: [NSPredicate]) -> NSPredicate? {
        parts.count <= 1 ? parts.first : NSCompoundPredicate(orPredicateWithSubpredicates: parts)
    }
}
