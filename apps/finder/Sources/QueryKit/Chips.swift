import Foundation

public enum QueryChips {
    public static func describe(_ query: ParsedQuery) -> [String] {
        var chips: [String] = []
        if let root = query.root {
            if case .and(let children) = root {
                chips = children.map { phrase($0) }
            } else {
                chips = [phrase(root)]
            }
        }
        if let sort = query.sort {
            chips.append("sorted by " + sortLabel(sort))
        }
        return chips
    }

    static func phrase(_ node: Node) -> String {
        switch node {
        case .term(let term):
            return phrase(term)
        case .and(let children):
            return children.map { phrase($0) }.joined(separator: " and ")
        case .or(let children):
            return children.map { (child: Node) -> String in
                if case .and = child { return "(" + phrase(child) + ")" }
                return phrase(child)
            }.joined(separator: " or ")
        case .not(let inner):
            switch inner {
            case .and, .or: return "not (" + phrase(inner) + ")"
            default: return "not " + phrase(inner)
            }
        case .saved(let name):
            return "@" + name
        }
    }

    static func phrase(_ term: Term) -> String {
        switch term {
        case .text(let pattern):
            return display(pattern)
        case .field(let field, let pattern):
            switch field {
            case .name: return pattern.style == .prefix ? "name starts with " + pattern.text : "name has " + display(pattern)
            case .content: return "text has " + display(pattern)
            case .ext: return pattern.text.hasPrefix(".") ? pattern.text : "." + pattern.text
            case .from: return "from " + pattern.text
            case .tag: return "tagged " + display(pattern)
            case .author: return "by " + display(pattern)
            }
        case .kind(let kind):
            return kind.label
        case .folder(let folder):
            return "in " + folder
        case .location(.googleDrive):
            return "in Google Drive"
        case .location(.local):
            return "on this Mac"
        case .date(let field, let comparison):
            return datePhrase(field, comparison)
        case .size(let comparison):
            return sizePhrase(comparison)
        case .pages(let comparison):
            return pagesPhrase(comparison)
        }
    }

    private static func display(_ pattern: Pattern) -> String {
        switch pattern.style {
        case .word: return pattern.text
        case .phrase: return "\"" + pattern.text + "\""
        case .prefix: return pattern.text + "\u{2026}"
        }
    }

    private static func sortLabel(_ key: SortKey) -> String {
        switch key {
        case .modified: return "date modified"
        case .size: return "size"
        case .name: return "name"
        }
    }

    // MARK: Dates

    private static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private static func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }

    private static func label(_ spec: DateSpec) -> String {
        switch spec {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .daysAgo(let count): return days(count) + " ago"
        case .year(let year): return "\(year)"
        case .month(let year, let month): return "\(months[month - 1]) \(year)"
        case .day(let year, let month, let day): return "\(months[month - 1]) \(day), \(year)"
        }
    }

    private static func preposition(_ spec: DateSpec) -> String {
        switch spec {
        case .year, .month: return "in"
        default: return "on"
        }
    }

    private static func datePhrase(_ field: DateField, _ comparison: Comparison<DateSpec>) -> String {
        let verb: String
        switch field {
        case .modified: verb = "changed"
        case .created: verb = "created"
        case .opened: verb = "opened"
        }
        switch comparison {
        case .between(let a, let b):
            return "\(verb) between \(label(a)) and \(label(b))"
        case .equal(let spec), .less(let spec), .lessOrEqual(let spec):
            if case .daysAgo(let count) = spec {
                return verb + (count == 1 ? " in the last day" : " in the last \(count) days")
            }
            if case .equal = comparison {
                switch spec {
                case .today, .yesterday: return "\(verb) \(label(spec))"
                default: return "\(verb) \(preposition(spec)) \(label(spec))"
                }
            }
            if case .less = comparison { return "\(verb) before \(label(spec))" }
            return "\(verb) \(preposition(spec)) or before \(label(spec))"
        case .greater(let spec), .greaterOrEqual(let spec):
            if case .daysAgo(let count) = spec {
                return "\(verb) more than \(days(count)) ago"
            }
            if case .greater = comparison { return "\(verb) after \(label(spec))" }
            return "\(verb) \(preposition(spec)) or after \(label(spec))"
        }
    }

    // MARK: Numbers

    static func bytes(_ count: Int64) -> String {
        let units: [(Int64, String)] = [(1_000_000_000, "GB"), (1_000_000, "MB"), (1_000, "KB")]
        for (size, name) in units where count >= size {
            var number = String(format: "%.1f", Double(count) / Double(size))
            if number.hasSuffix(".0") { number.removeLast(2) }
            return number + " " + name
        }
        return count == 1 ? "1 byte" : "\(count) bytes"
    }

    private static func sizePhrase(_ comparison: Comparison<Int64>) -> String {
        switch comparison {
        case .equal(let v): return "exactly " + bytes(v)
        case .less(let v): return "smaller than " + bytes(v)
        case .lessOrEqual(let v): return "at most " + bytes(v)
        case .greater(let v): return "larger than " + bytes(v)
        case .greaterOrEqual(let v): return "at least " + bytes(v)
        case .between(let a, let b): return "between \(bytes(min(a, b))) and \(bytes(max(a, b)))"
        }
    }

    private static func pagesPhrase(_ comparison: Comparison<Int64>) -> String {
        func pages(_ n: Int64) -> String { n == 1 ? "1 page" : "\(n) pages" }
        switch comparison {
        case .equal(let v): return pages(v)
        case .less(let v): return "fewer than " + pages(v)
        case .lessOrEqual(let v): return "at most " + pages(v)
        case .greater(let v): return "more than " + pages(v)
        case .greaterOrEqual(let v): return "at least " + pages(v)
        case .between(let a, let b): return "\(min(a, b)) to \(pages(max(a, b)))"
        }
    }
}
