import Foundation

/// The part of YAML that Espanso match files use: block maps and lists, flow
/// [lists] and {maps}, plain, 'single' and "double" quoted scalars, | and >
/// block scalars, and comments. Anchors, tags and multi-document files are not read.
public indirect enum YAMLValue: Sendable, Equatable {
    case scalar(String)
    case list([YAMLValue])
    case map([String: YAMLValue])

    public var string: String? { if case .scalar(let s) = self { return s }; return nil }
    public var array: [YAMLValue]? { if case .list(let l) = self { return l }; return nil }
    public subscript(key: String) -> YAMLValue? { if case .map(let m) = self { return m[key] }; return nil }
}

public enum MiniYAML {
    struct Line {
        var indent: Int
        var text: String
        let raw: String
    }

    public static func parse(_ text: String) -> YAMLValue? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> Line in
            let s = String(raw).replacingOccurrences(of: "\t", with: "  ")
            let indent = s.prefix { $0 == " " }.count
            return Line(indent: indent, text: String(s.dropFirst(indent)), raw: s)
        }
        if lines.last?.text.isEmpty == true { lines.removeLast() }
        var i = 0
        skipBlank(lines, &i)
        guard i < lines.count else { return nil }
        return block(&lines, &i, indent: lines[i].indent)
    }

    static func isBlank(_ line: Line) -> Bool {
        line.text.isEmpty || line.text.hasPrefix("#") || line.text == "---"
    }

    static func skipBlank(_ lines: [Line], _ i: inout Int) {
        while i < lines.count, isBlank(lines[i]) { i += 1 }
    }

    static func isListItem(_ text: String) -> Bool { text == "-" || text.hasPrefix("- ") }

    static func block(_ lines: inout [Line], _ i: inout Int, indent: Int) -> YAMLValue {
        isListItem(lines[i].text) ? list(&lines, &i, indent: indent) : map(&lines, &i, indent: indent)
    }

    static func list(_ lines: inout [Line], _ i: inout Int, indent: Int) -> YAMLValue {
        var items: [YAMLValue] = []
        while true {
            skipBlank(lines, &i)
            guard i < lines.count, lines[i].indent == indent, isListItem(lines[i].text) else { break }
            let content = String(lines[i].text.dropFirst()).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                i += 1
                skipBlank(lines, &i)
                if i < lines.count, lines[i].indent > indent { items.append(block(&lines, &i, indent: lines[i].indent)) }
                else { items.append(.scalar("")) }
            } else if keyValue(content) != nil {
                // "- key: value" opens a map whose keys line up with "key".
                let column = indent + (lines[i].text.count - content.count)
                lines[i] = Line(indent: column, text: content, raw: lines[i].raw)
                items.append(map(&lines, &i, indent: column))
            } else {
                i += 1
                items.append(inlineValue(content, &lines, &i, indent: indent))
            }
        }
        return .list(items)
    }

    static func map(_ lines: inout [Line], _ i: inout Int, indent: Int) -> YAMLValue {
        var result: [String: YAMLValue] = [:]
        while true {
            skipBlank(lines, &i)
            guard i < lines.count, lines[i].indent == indent, !isListItem(lines[i].text),
                  let pair = keyValue(lines[i].text) else { break }
            let (key, value) = pair
            i += 1
            if value.isEmpty {
                skipBlank(lines, &i)
                if i < lines.count, lines[i].indent > indent || (lines[i].indent == indent && isListItem(lines[i].text)) {
                    result[key] = block(&lines, &i, indent: lines[i].indent)
                } else {
                    result[key] = .scalar("")
                }
            } else {
                result[key] = inlineValue(value, &lines, &i, indent: indent)
            }
        }
        return .map(result)
    }

    /// A value on the same line as its key or dash: a block scalar, a flow collection or a scalar.
    static func inlineValue(_ value: String, _ lines: inout [Line], _ i: inout Int, indent: Int) -> YAMLValue {
        if let style = value.first, style == "|" || style == ">" {
            return .scalar(blockScalar(folded: style == ">", chomp: value.dropFirst().first, &lines, &i, indent: indent))
        }
        if value.hasPrefix("[") || value.hasPrefix("{") {
            var text = value
            while !balanced(text), i < lines.count {
                text += " " + lines[i].text
                i += 1
            }
            var reader = FlowReader(Array(text))
            return reader.value()
        }
        return .scalar(scalar(stripComment(value)))
    }

    static func blockScalar(folded: Bool, chomp: Character?, _ lines: inout [Line], _ i: inout Int, indent: Int) -> String {
        var body: [String] = []
        var margin: Int?
        while i < lines.count {
            let line = lines[i]
            if line.text.isEmpty { body.append(""); i += 1; continue }
            guard line.indent > indent else { break }
            let m = margin ?? line.indent
            margin = m
            body.append(String(line.raw.dropFirst(min(m, line.indent))))
            i += 1
        }
        while body.last == "" { body.removeLast() }
        var text = folded ? fold(body) : body.joined(separator: "\n")
        if chomp != "-" { text += "\n" }
        return text
    }

    static func fold(_ lines: [String]) -> String {
        var out = ""
        for line in lines {
            if line.isEmpty { out += "\n"; continue }
            if !out.isEmpty, !out.hasSuffix("\n") { out += " " }
            out += line
        }
        return out
    }

    /// "key: value" or "key:", outside quotes.
    static func keyValue(_ text: String) -> (String, String)? {
        var quote: Character?
        let chars = Array(text)
        for (k, c) in chars.enumerated() {
            if let q = quote { if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { if k == 0 { quote = c }; continue }
            if c == ":" && (k == chars.count - 1 || chars[k + 1] == " ") {
                let key = scalar(String(chars[..<k]).trimmingCharacters(in: .whitespaces))
                let value = String(chars[(k + 1)...]).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : (key, value)
            }
            if c == "[" || c == "{" { return nil }
        }
        return nil
    }

    static func stripComment(_ text: String) -> String {
        guard let first = text.first, first != "\"", first != "'" else { return text }
        if let range = text.range(of: " #") { return String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return text
    }

    static func balanced(_ text: String) -> Bool {
        var depth = 0
        var quote: Character?
        for c in text {
            if let q = quote { if c == q { quote = nil }; continue }
            switch c {
            case "\"", "'": quote = c
            case "[", "{": depth += 1
            case "]", "}": depth -= 1
            default: break
            }
        }
        return depth <= 0
    }

    static func scalar(_ text: String) -> String {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            return unescape(String(text.dropFirst().dropLast()))
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return text
    }

    static func unescape(_ text: String) -> String {
        var out = ""
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            guard c == "\\", let next = chars.popFirst() else { out.append(c); continue }
            switch next {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            case "u":
                let hex = String(chars.prefix(4))
                chars = chars.dropFirst(4)
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) }
            default: out.append(next)
            }
        }
        return out
    }
}

/// Reads [a, b] and {k: v} on one (joined) line.
struct FlowReader {
    let chars: [Character]
    var i = 0

    init(_ chars: [Character]) { self.chars = chars }

    mutating func skipSpace() { while i < chars.count, chars[i] == " " { i += 1 } }

    mutating func value() -> YAMLValue {
        skipSpace()
        guard i < chars.count else { return .scalar("") }
        if chars[i] == "[" { return list() }
        if chars[i] == "{" { return map() }
        return .scalar(scalarText(stops: ",]}"))
    }

    mutating func list() -> YAMLValue {
        i += 1
        var items: [YAMLValue] = []
        while true {
            skipSpace()
            guard i < chars.count else { break }
            if chars[i] == "]" { i += 1; break }
            if chars[i] == "," { i += 1; continue }
            items.append(value())
        }
        return .list(items)
    }

    mutating func map() -> YAMLValue {
        i += 1
        var result: [String: YAMLValue] = [:]
        while true {
            skipSpace()
            guard i < chars.count else { break }
            if chars[i] == "}" { i += 1; break }
            if chars[i] == "," { i += 1; continue }
            let key = scalarText(stops: ":,}")
            skipSpace()
            if i < chars.count, chars[i] == ":" {
                i += 1
                result[key] = value()
            } else {
                result[key] = .scalar("")
            }
        }
        return .map(result)
    }

    mutating func scalarText(stops: String) -> String {
        skipSpace()
        guard i < chars.count else { return "" }
        if chars[i] == "\"" || chars[i] == "'" {
            let quote = chars[i]
            var j = i + 1
            while j < chars.count {
                if chars[j] == "\\", quote == "\"" { j += 2; continue }
                if chars[j] == quote {
                    if quote == "'", j + 1 < chars.count, chars[j + 1] == "'" { j += 2; continue }
                    break
                }
                j += 1
            }
            let text = String(chars[i...min(j, chars.count - 1)])
            i = min(j + 1, chars.count)
            return MiniYAML.scalar(text)
        }
        var j = i
        while j < chars.count, !stops.contains(chars[j]) { j += 1 }
        let text = String(chars[i..<j]).trimmingCharacters(in: .whitespaces)
        i = j
        return text
    }
}
