import Foundation

/// A value read from a TOML file.
public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case array([TOMLValue])

    /// A short name for messages ("a number", "text").
    public var kindName: String {
        switch self {
        case .string: return "text"
        case .integer, .float: return "a number"
        case .bool: return "true or false"
        case .array: return "a list"
        }
    }
}

/// A parsed file: its values, and the line each key is on.
public struct TOMLDocument: Equatable, Sendable {
    public var values: [String: TOMLValue]
    public var lines: [String: Int]

    public init(values: [String: TOMLValue], lines: [String: Int] = [:]) {
        self.values = values
        self.lines = lines
    }
}

public struct TOMLError: Error, Equatable, Sendable, CustomStringConvertible {
    public var line: Int
    public var message: String
    public var description: String { "line \(line): \(message)" }
}

/// The part of TOML that widget and settings files need: comments, `[tables]`,
/// bare, quoted and dotted keys, all four string forms, integers, floats,
/// booleans and arrays (across lines too). Keys inside a table come back
/// joined with dots ("weather.units"). Dates, inline tables and arrays of
/// tables are reported as unsupported rather than misread.
public enum TOML {
    public static func parse(_ text: String) throws -> [String: TOMLValue] {
        try parseDocument(text).values
    }

    /// The values and the line each key was written on, for messages that
    /// name the line to fix.
    public static func parseDocument(_ text: String) throws -> TOMLDocument {
        var parser = Parser(text)
        let values = try parser.document()
        return TOMLDocument(values: values, lines: parser.keyLines)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0
        var line = 1
        var depth = 0
        /// The line of each key, by its full dotted name.
        var keyLines: [String: Int] = [:]
        /// Lists nested deeper than this are refused, so a hostile file
        /// cannot exhaust the stack.
        static let maxDepth = 32

        init(_ text: String) {
            var chars = Array(text)
            if chars.first == "\u{FEFF}" { chars.removeFirst() }
            self.chars = chars
        }

        var atEnd: Bool { index >= chars.count }
        func peek(_ offset: Int = 0) -> Character? {
            let i = index + offset
            return i < chars.count ? chars[i] : nil
        }
        mutating func advance() {
            if let c = peek(), c.isNewline { line += 1 }
            index += 1
        }
        func fail(_ message: String) -> TOMLError { TOMLError(line: line, message: message) }

        mutating func skipSpaces() {
            while let c = peek(), c == " " || c == "\t" { advance() }
        }
        mutating func skipComment() {
            if peek() == "#" { while let c = peek(), !c.isNewline { advance() } }
        }
        /// Spaces, new lines and comments, between entries and inside arrays.
        mutating func skipBlank() {
            while let c = peek() {
                if c == " " || c == "\t" || c.isNewline { advance() }
                else if c == "#" { skipComment() }
                else { break }
            }
        }
        mutating func expectLineEnd() throws {
            skipSpaces()
            skipComment()
            guard let c = peek() else { return }
            guard c.isNewline else { throw fail("expected a new line after the value, found \"\(c)\"") }
            advance()
        }

        mutating func document() throws -> [String: TOMLValue] {
            var result: [String: TOMLValue] = [:]
            var tables: Set<String> = []
            var prefix = ""
            while true {
                skipBlank()
                guard let c = peek() else { break }
                if c == "[" {
                    if peek(1) == "[" { throw fail("arrays of tables ([[name]]) are not supported") }
                    advance()
                    skipSpaces()
                    let name = try keyPath().joined(separator: ".")
                    skipSpaces()
                    guard peek() == "]" else { throw fail("expected \"]\" to close the table name") }
                    advance()
                    guard tables.insert(name).inserted else { throw fail("table [\(name)] appears twice") }
                    prefix = name
                    try expectLineEnd()
                } else {
                    let keyLine = line
                    let key = try keyPath().joined(separator: ".")
                    skipSpaces()
                    guard peek() == "=" else { throw fail("expected \"=\" after the key \"\(key)\"") }
                    advance()
                    skipSpaces()
                    let value = try self.value()
                    try expectLineEnd()
                    let full = prefix.isEmpty ? key : "\(prefix).\(key)"
                    guard result[full] == nil else {
                        throw TOMLError(line: keyLine, message: "the key \"\(full)\" appears twice")
                    }
                    result[full] = value
                    keyLines[full] = keyLine
                }
            }
            return result
        }

        static func isBare(_ c: Character) -> Bool {
            c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "-")
        }

        mutating func keyPath() throws -> [String] {
            var parts: [String] = []
            while true {
                skipSpaces()
                guard let c = peek() else { throw fail("expected a key") }
                if c == "\"" {
                    advance()
                    parts.append(try basicString())
                } else if c == "'" {
                    advance()
                    parts.append(try literalString())
                } else if Parser.isBare(c) {
                    var part = ""
                    while let c = peek(), Parser.isBare(c) { part.append(c); advance() }
                    parts.append(part)
                } else {
                    throw fail(parts.isEmpty ? "expected a key, found \"\(c)\"" : "expected a key after \".\"")
                }
                skipSpaces()
                if peek() == "." { advance() } else { break }
            }
            return parts
        }

        mutating func value() throws -> TOMLValue {
            guard let c = peek(), !c.isNewline else { throw fail("expected a value after \"=\"") }
            switch c {
            case "\"":
                if peek(1) == "\"" && peek(2) == "\"" {
                    advance(); advance(); advance()
                    return .string(try multilineBasicString())
                }
                advance()
                return .string(try basicString())
            case "'":
                if peek(1) == "'" && peek(2) == "'" {
                    advance(); advance(); advance()
                    return .string(try multilineLiteralString())
                }
                advance()
                return .string(try literalString())
            case "[":
                guard depth < Parser.maxDepth else { throw fail("lists are nested too deeply") }
                advance()
                depth += 1
                defer { depth -= 1 }
                return try array()
            case "{":
                throw fail("inline tables ({ ... }) are not supported; use a [table] instead")
            default:
                return try scalar()
            }
        }

        mutating func array() throws -> TOMLValue {
            var items: [TOMLValue] = []
            while true {
                skipBlank()
                guard let c = peek() else { throw fail("the list is not closed with \"]\"") }
                if c == "]" { advance(); return .array(items) }
                items.append(try value())
                skipBlank()
                guard let next = peek() else { throw fail("the list is not closed with \"]\"") }
                if next == "," { advance(); continue }
                if next == "]" { advance(); return .array(items) }
                throw fail("expected \",\" or \"]\" in the list, found \"\(next)\"")
            }
        }

        mutating func scalar() throws -> TOMLValue {
            var token = ""
            while let c = peek(), !(c == " " || c == "\t" || c.isNewline || c == "," || c == "]" || c == "#") {
                token.append(c)
                advance()
            }
            if token == "true" { return .bool(true) }
            if token == "false" { return .bool(false) }
            let digits = token.replacingOccurrences(of: "_", with: "")
            if digits.hasPrefix("0x"), let n = Int(digits.dropFirst(2), radix: 16) { return .integer(n) }
            if let n = Int(digits) { return .integer(n) }
            let looksNumeric = !digits.isEmpty && digits.allSatisfy { "0123456789+-.eE".contains($0) }
            if looksNumeric, let d = Double(digits) { return .float(d) }
            if token.isEmpty { throw fail("expected a value") }
            if token.count >= 10, token.prefix(4).allSatisfy(\.isNumber), token.dropFirst(4).first == "-" {
                throw fail("dates are not supported; write \"\(token)\" in quotes")
            }
            throw fail("\"\(token)\" is not a value; text needs quotes")
        }

        mutating func escape() throws -> String {
            guard let c = peek() else { throw fail("the text is not closed") }
            advance()
            switch c {
            case "b": return "\u{08}"
            case "t": return "\t"
            case "n": return "\n"
            case "f": return "\u{0C}"
            case "r": return "\r"
            case "e": return "\u{1B}"
            case "\"": return "\""
            case "\\": return "\\"
            case "u", "U":
                let count = c == "u" ? 4 : 8
                var hex = ""
                for _ in 0..<count {
                    guard let h = peek(), h.isHexDigit else { throw fail("\\\(c) needs \(count) hex digits") }
                    hex.append(h)
                    advance()
                }
                guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw fail("\\\(c)\(hex) is not a character")
                }
                return String(Character(scalar))
            default:
                throw fail("unknown escape \"\\\(c)\" (write \\\\ for a backslash)")
            }
        }

        mutating func basicString() throws -> String {
            var out = ""
            while true {
                guard let c = peek(), !c.isNewline else { throw fail("the text is not closed with \"") }
                advance()
                if c == "\"" { return out }
                if c == "\\" { out += try escape() } else { out.append(c) }
            }
        }

        mutating func literalString() throws -> String {
            var out = ""
            while true {
                guard let c = peek(), !c.isNewline else { throw fail("the text is not closed with '") }
                advance()
                if c == "'" { return out }
                out.append(c)
            }
        }

        mutating func multilineBasicString() throws -> String {
            if let c = peek(), c.isNewline { advance() }
            var out = ""
            while true {
                guard let c = peek() else { throw fail("the text is not closed with \"\"\"") }
                if c == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                    advance(); advance(); advance()
                    // Up to two more quotes belong to the text.
                    while peek() == "\"" { out.append("\""); advance() }
                    return out
                }
                advance()
                if c == "\\" {
                    // A backslash at the end of a line joins it to the next.
                    var look = 0
                    while let s = peek(look), s == " " || s == "\t" { look += 1 }
                    if let s = peek(look), s.isNewline {
                        while let s = peek(), s == " " || s == "\t" || s.isNewline { advance() }
                    } else {
                        out += try escape()
                    }
                } else {
                    out.append(c)
                }
            }
        }

        mutating func multilineLiteralString() throws -> String {
            if let c = peek(), c.isNewline { advance() }
            var out = ""
            while true {
                guard let c = peek() else { throw fail("the text is not closed with '''") }
                if c == "'" && peek(1) == "'" && peek(2) == "'" {
                    advance(); advance(); advance()
                    while peek() == "'" { out.append("'"); advance() }
                    return out
                }
                advance()
                out.append(c)
            }
        }
    }
}
