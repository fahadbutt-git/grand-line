import Foundation

struct RawValue: Equatable {
    let text: String
    let quoted: Bool
    let range: Range<Int>
}

struct Token: Equatable {
    enum Kind: Equatable {
        case open
        case close
        case or
        case not
        case word(String, quoted: Bool)
        case filter(key: String, keyRange: Range<Int>, values: [RawValue])
        case saved(String)
    }

    let kind: Kind
    let range: Range<Int>
}

struct Lexer {
    private let chars: [Character]
    private var index = 0
    private var tokens: [Token] = []
    private var issues: [QueryIssue] = []

    private init(chars: [Character]) {
        self.chars = chars
    }

    static func tokenize(_ text: String) -> (tokens: [Token], issues: [QueryIssue]) {
        var lexer = Lexer(chars: Array(text))
        lexer.run()
        return (lexer.tokens, lexer.issues)
    }

    static func opensQuote(_ c: Character) -> Bool {
        c == "\"" || c == "\u{201C}" || c == "\u{201D}"
    }

    static func closesQuote(_ c: Character) -> Bool {
        c == "\"" || c == "\u{201D}" || c == "\u{201C}"
    }

    private static func isDelimiter(_ c: Character, comma: Bool) -> Bool {
        c.isWhitespace || c == "(" || c == ")" || c == "|" || (comma && c == ",")
    }

    private mutating func run() {
        while index < chars.count {
            let start = index
            let c = chars[index]
            if c.isWhitespace {
                index += 1
                continue
            }
            switch c {
            case "(":
                index += 1
                emit(.open, from: start)
            case ")":
                index += 1
                emit(.close, from: start)
            case "|":
                index += 1
                emit(.or, from: start)
            case "-":
                index += 1
                if index < chars.count, !Lexer.isDelimiter(chars[index], comma: false) {
                    emit(.not, from: start)
                } else {
                    issues.append(QueryIssue(kind: .danglingOperator, message: "Nothing to negate", range: start..<index))
                }
            case "@":
                lexSaved(from: start)
            default:
                if Lexer.opensQuote(c) {
                    let text = readQuoted().trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty { emit(.word(text, quoted: true), from: start) }
                } else {
                    lexBare(from: start)
                }
            }
        }
    }

    private mutating func emit(_ kind: Token.Kind, from start: Int) {
        tokens.append(Token(kind: kind, range: start..<index))
    }

    private mutating func readQuoted() -> String {
        let start = index
        index += 1
        var text = ""
        while index < chars.count, !Lexer.closesQuote(chars[index]) {
            text.append(chars[index])
            index += 1
        }
        if index < chars.count {
            index += 1
        } else {
            issues.append(QueryIssue(kind: .unclosedQuote, message: "Missing closing quote", range: start..<index))
        }
        return text
    }

    private mutating func readBare(stopAtComma: Bool) -> String {
        var text = ""
        while index < chars.count, !Lexer.isDelimiter(chars[index], comma: stopAtComma) {
            text.append(chars[index])
            index += 1
        }
        return text
    }

    private mutating func readValues() -> [RawValue] {
        var values: [RawValue] = []
        while true {
            let start = index
            if index < chars.count, Lexer.opensQuote(chars[index]) {
                let text = readQuoted()
                values.append(RawValue(text: text, quoted: true, range: start..<index))
            } else {
                let text = readBare(stopAtComma: true)
                values.append(RawValue(text: text, quoted: false, range: start..<index))
            }
            guard index < chars.count, chars[index] == "," else { return values }
            index += 1
        }
    }

    private mutating func lexSaved(from start: Int) {
        index += 1
        let name: String
        if index < chars.count, Lexer.opensQuote(chars[index]) {
            name = readQuoted().trimmingCharacters(in: .whitespaces)
        } else {
            name = readBare(stopAtComma: false)
        }
        if name.isEmpty {
            issues.append(QueryIssue(kind: .badValue, message: "A saved search needs a name after @", range: start..<index))
        } else {
            emit(.saved(name), from: start)
        }
    }

    private mutating func lexBare(from start: Int) {
        var end = start
        while end < chars.count, chars[end].isASCII, chars[end].isLetter {
            end += 1
        }
        if end > start, end < chars.count, chars[end] == ":" {
            let key = String(chars[start..<end])
            index = end + 1
            let values = readValues()
            emit(.filter(key: key, keyRange: start..<end, values: values), from: start)
            return
        }
        let word = readBare(stopAtComma: false)
        switch word.lowercased() {
        case "or": emit(.or, from: start)
        case "not": emit(.not, from: start)
        default: emit(.word(word, quoted: false), from: start)
        }
    }
}
