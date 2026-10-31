import Foundation

public enum QueryParser {
    public static func parse(_ text: String) -> ParsedQuery {
        let lexed = Lexer.tokenize(text)
        var parser = Parser(tokens: lexed.tokens)
        let root = parser.parseQuery()
        let issues = (lexed.issues + parser.issues).sorted {
            ($0.range.lowerBound, $0.range.upperBound) < ($1.range.lowerBound, $1.range.upperBound)
        }
        return ParsedQuery(root: root, issues: issues, sort: parser.sort)
    }
}

struct Parsed {
    let node: Node
    let range: Range<Int>
}

struct Parser {
    let tokens: [Token]
    var position = 0
    var issues: [QueryIssue] = []
    var sort: SortKey?

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token? {
        position < tokens.count ? tokens[position] : nil
    }

    mutating func report(_ kind: QueryIssue.Kind, _ message: String, _ range: Range<Int>) {
        guard !issues.contains(where: { $0.kind == kind && $0.range == range }) else { return }
        issues.append(QueryIssue(kind: kind, message: message, range: range))
    }

    mutating func parseQuery() -> Node? {
        var conjuncts: [Parsed] = []
        while true {
            conjuncts += parseOr().conjuncts
            guard let stray = current else { break }
            report(.unbalancedBracket, "This bracket has no opening bracket", stray.range)
            position += 1
        }
        for conjunct in conjuncts where conjunct.node.mixesFolders {
            report(.misplacedFolder, "Folder filters apply to the whole search and cannot share an OR or NOT with other terms", conjunct.range)
        }
        return Parser.conjunction(conjuncts)?.node
    }

    private mutating func parseOr() -> (node: Parsed?, conjuncts: [Parsed], consumed: Bool) {
        var alternatives: [Parsed] = []
        var firstConjuncts: [Parsed] = []
        var pendingOr: Token?
        var consumedAny = false
        while true {
            let (items, consumed) = parseAnd()
            consumedAny = consumedAny || consumed
            if !consumed, let op = pendingOr {
                report(.danglingOperator, "Nothing after OR", op.range)
            }
            if let combined = Parser.conjunction(items) {
                if alternatives.isEmpty { firstConjuncts = items }
                alternatives.append(combined)
            }
            guard let token = current, token.kind == .or else { break }
            position += 1
            consumedAny = true
            if !consumed && pendingOr == nil {
                report(.danglingOperator, "Nothing before OR", token.range)
            }
            pendingOr = token
        }
        let node = Parser.disjunction(alternatives)
        let conjuncts = alternatives.count == 1 ? firstConjuncts : (node.map { [$0] } ?? [])
        return (node, conjuncts, consumedAny)
    }

    private mutating func parseAnd() -> ([Parsed], Bool) {
        var items: [Parsed] = []
        var consumed = false
        while let token = current, token.kind != .or, token.kind != .close {
            consumed = true
            if let item = parseUnary() { items.append(item) }
        }
        return (items, consumed)
    }

    private mutating func parseUnary() -> Parsed? {
        guard let token = current else { return nil }
        guard token.kind == .not else { return parsePrimary() }
        position += 1
        guard let next = current, next.kind != .or, next.kind != .close else {
            report(.danglingOperator, "Nothing to negate", token.range)
            return nil
        }
        guard let operand = parseUnary() else { return nil }
        return Parsed(node: .not(operand.node), range: token.range.lowerBound..<operand.range.upperBound)
    }

    private mutating func parsePrimary() -> Parsed? {
        guard let token = current else { return nil }
        position += 1
        switch token.kind {
        case .open:
            let inner = parseOr()
            guard let close = current, close.kind == .close else {
                report(.unbalancedBracket, "This bracket is never closed", token.range)
                return inner.node
            }
            position += 1
            let range = token.range.lowerBound..<close.range.upperBound
            if !inner.consumed {
                report(.emptyGroup, "Empty brackets", range)
            }
            return inner.node.map { Parsed(node: $0.node, range: range) }
        case .word(let text, quoted: let quoted):
            return Pattern.parse(text, quoted: quoted).map { Parsed(node: .term(.text($0)), range: token.range) }
        case .saved(let name):
            return Parsed(node: .saved(name), range: token.range)
        case .filter(key: let key, keyRange: let keyRange, values: let values):
            return filterNode(key: key, keyRange: keyRange, values: values, range: token.range)
                .map { Parsed(node: $0, range: token.range) }
        case .close, .or, .not:
            return nil
        }
    }

    static func conjunction(_ items: [Parsed]) -> Parsed? {
        guard let first = items.first, let last = items.last else { return nil }
        if items.count == 1 { return first }
        var nodes: [Node] = []
        for item in items {
            if case .and(let inner) = item.node { nodes += inner } else { nodes.append(item.node) }
        }
        return Parsed(node: .and(nodes), range: first.range.lowerBound..<last.range.upperBound)
    }

    static func disjunction(_ items: [Parsed]) -> Parsed? {
        guard let first = items.first, let last = items.last else { return nil }
        if items.count == 1 { return first }
        var nodes: [Node] = []
        for item in items {
            if case .or(let inner) = item.node { nodes += inner } else { nodes.append(item.node) }
        }
        return Parsed(node: .or(nodes), range: first.range.lowerBound..<last.range.upperBound)
    }
}
