import Foundation

/// Arithmetic: + − × ÷ ^ %, parentheses, functions (sqrt, ln, log, sin…),
/// constants (pi, e), "x% of y", and "a + b%" as a percentage of a.
public enum Expression {
    enum Token: Equatable {
        case number(Double)
        case op(Character)
        case word(String)
        case open
        case close
    }

    /// nil when the text is not a complete expression.
    public static func evaluate(_ text: String) -> Double? {
        guard let tokens = tokenize(text), !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.sum(), parser.atEnd, value.value.isFinite else { return nil }
        return value.value
    }

    /// Whether the text does more than state a number: an operator or a function.
    public static func hasWork(_ text: String) -> Bool {
        guard let tokens = tokenize(text) else { return false }
        return tokens.contains { token in
            switch token {
            case .op, .open: return true
            case .word(let w): return functions[w] != nil
            default: return false
            }
        } && tokens.count > 1
    }

    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": { cbrt($0) }, "abs": { abs($0) },
        "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
    ]

    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi]

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                var digits = ""
                while j < chars.count {
                    let d = chars[j]
                    if d.isNumber || d == "." { digits.append(d); j += 1; continue }
                    // 1,000,000: a comma followed by exactly three digits.
                    if d == ",", j + 3 < chars.count, chars[j + 1].isNumber, chars[j + 2].isNumber, chars[j + 3].isNumber,
                       j + 4 == chars.count || !chars[j + 4].isNumber {
                        j += 1
                        continue
                    }
                    // 1e3, 2.5e-4
                    if d == "e" || d == "E", j + 1 < chars.count,
                       chars[j + 1].isNumber || ((chars[j + 1] == "-" || chars[j + 1] == "+") && j + 2 < chars.count && chars[j + 2].isNumber) {
                        digits.append("e")
                        digits.append(chars[j + 1])
                        j += 2
                        continue
                    }
                    break
                }
                guard let value = Double(digits) else { return nil }
                tokens.append(.number(value))
                i = j
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^", "%", "×", "÷", "−", "·":
                let op: Character = c == "×" || c == "·" ? "*" : c == "÷" ? "/" : c == "−" ? "-" : c
                tokens.append(.op(op))
                i += 1
                continue
            case "(":
                tokens.append(.open); i += 1; continue
            case ")":
                tokens.append(.close); i += 1; continue
            default:
                break
            }
            if c.isLetter || c == "π" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber { j += 1 }
                let word = String(chars[i..<j]).lowercased()
                if word == "of" || word == "x" { tokens.append(.op("*")) }
                else if word == "mod" { tokens.append(.op("m")) }
                else { tokens.append(.word(word)) }
                i = j
                continue
            }
            return nil
        }
        return tokens
    }

    struct Value {
        var value: Double
        var percent = false
    }

    struct Parser {
        let tokens: [Token]
        var i = 0

        var atEnd: Bool { i == tokens.count }
        var peek: Token? { i < tokens.count ? tokens[i] : nil }

        mutating func sum() -> Value? {
            guard var left = product() else { return nil }
            while case .op(let op)? = peek, op == "+" || op == "-" {
                i += 1
                guard let right = product() else { return nil }
                let amount = right.percent ? left.value * right.value : right.value
                left = Value(value: op == "+" ? left.value + amount : left.value - amount)
            }
            return left
        }

        mutating func product() -> Value? {
            guard var left = unary() else { return nil }
            while case .op(let op)? = peek, op == "*" || op == "/" || op == "m" {
                i += 1
                guard let right = unary() else { return nil }
                switch op {
                case "*": left = Value(value: left.value * right.value)
                case "/": left = Value(value: left.value / right.value)
                default: left = Value(value: left.value.truncatingRemainder(dividingBy: right.value))
                }
            }
            return left
        }

        mutating func unary() -> Value? {
            if case .op(let op)? = peek, op == "-" || op == "+" {
                i += 1
                guard let inner = unary() else { return nil }
                return Value(value: op == "-" ? -inner.value : inner.value, percent: inner.percent)
            }
            return power()
        }

        mutating func power() -> Value? {
            guard let base = postfix() else { return nil }
            if case .op("^")? = peek {
                i += 1
                guard let exponent = unary() else { return nil }
                return Value(value: pow(base.value, exponent.value))
            }
            return base
        }

        mutating func postfix() -> Value? {
            guard var value = primary() else { return nil }
            while case .op("%")? = peek {
                i += 1
                value = Value(value: value.value / 100, percent: true)
            }
            return value
        }

        mutating func primary() -> Value? {
            guard let token = peek else { return nil }
            i += 1
            switch token {
            case .number(let n):
                return Value(value: n)
            case .open:
                guard let inner = sum(), case .close? = peek else { return nil }
                i += 1
                return Value(value: inner.value)
            case .word(let word):
                if let f = Expression.functions[word] {
                    guard let argument = postfix() else { return nil }
                    return Value(value: f(argument.value))
                }
                if let c = Expression.constants[word] { return Value(value: c) }
                return nil
            default:
                return nil
            }
        }
    }
}
