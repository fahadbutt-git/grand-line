import Foundation

/// Changes one top-level key of a TOML file and leaves every other line as
/// it was, comments and blank lines included. Den Den's Settings window
/// writes denden.toml through this, so a file you wrote by hand stays yours.
public enum TOMLEditor {
    /// `value` written as TOML.
    public static func literal(_ value: TOMLValue) -> String {
        switch value {
        case .string(let s): return quoted(s)
        case .integer(let n): return String(n)
        case .float(let d): return d.isFinite ? String(d) : "0.0"
        case .bool(let b): return b ? "true" : "false"
        case .array(let items): return "[" + items.map(literal).joined(separator: ", ") + "]"
        }
    }

    static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// The text with `key` set to `value`: the old value replaced in place
    /// (its comment kept), or a new line after the other top-level keys.
    /// Throws if the text is not TOML this parser reads, or the edit would
    /// not read back as `value`.
    public static func setting(_ key: String, to value: TOMLValue, in text: String) throws -> String {
        _ = try TOML.parse(text)
        let chars = Array(text)
        let scan = Scan(chars)
        let lit = Array(literal(value))
        var out: [Character]
        if let entry = scan.entries.first(where: { $0.key == key }) {
            out = Array(chars[..<entry.valueStart]) + lit + Array(chars[entry.valueEnd...])
        } else {
            let at = scan.entries.last?.lineEnd ?? scan.topLevelEnd
            var line = Array(barekey(key) + " = ") + lit + ["\n"]
            if at > 0, !chars[at - 1].isNewline { line.insert("\n", at: 0) }
            // Before the first [table] of a file with no top-level keys: keep a blank line between.
            if scan.entries.isEmpty, at < chars.count { line.append("\n") }
            out = Array(chars[..<at]) + line + Array(chars[at...])
        }
        let result = String(out)
        let reread = try TOML.parse(result)
        guard reread[key] == value else { throw TOMLError(line: 0, message: "the change to \(key) did not read back") }
        return result
    }

    /// The text without the line (or lines) that set `key`.
    public static func removing(_ key: String, in text: String) throws -> String {
        _ = try TOML.parse(text)
        let chars = Array(text)
        guard let entry = Scan(chars).entries.first(where: { $0.key == key }) else { return text }
        let result = String(Array(chars[..<entry.lineStart]) + Array(chars[entry.lineEnd...]))
        _ = try TOML.parse(result)
        return result
    }

    static func barekey(_ key: String) -> String {
        key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") } ? key : quoted(key)
    }

    /// Where each top-level `key = value` sits, by character index.
    struct Scan {
        struct Entry {
            var key: String
            var lineStart: Int
            var valueStart: Int
            /// Just past the value, before any spaces and comment.
            var valueEnd: Int
            /// Just past the line's end (or the text's end).
            var lineEnd: Int
        }

        var entries: [Entry] = []
        /// Where the first [table] starts, or the end of the text.
        var topLevelEnd: Int

        init(_ c: [Character]) {
            let n = c.count
            var i = 0
            topLevelEnd = n
            func skipToLineEnd(_ k: Int) -> Int {
                var k = k
                while k < n, !c[k].isNewline { k += 1 }
                return k < n ? k + 1 : n
            }
            while i < n {
                var j = i
                while j < n, c[j] == " " || c[j] == "\t" { j += 1 }
                if j >= n { break }
                if c[j].isNewline { i = j + 1; continue }
                if c[j] == "#" { i = skipToLineEnd(j); continue }
                if c[j] == "[" { topLevelEnd = i; break }
                // The key, up to "=" outside quotes.
                var key = ""
                var quote: Character?
                while j < n, !(quote == nil && c[j] == "="), !c[j].isNewline {
                    let ch = c[j]
                    if let q = quote { if ch == q { quote = nil } else { key.append(ch) } }
                    else if ch == "\"" || ch == "'" { quote = ch }
                    else if ch != " " && ch != "\t" { key.append(ch) }
                    j += 1
                }
                guard j < n, c[j] == "=" else { i = skipToLineEnd(j); continue }
                j += 1
                while j < n, c[j] == " " || c[j] == "\t" { j += 1 }
                let start = j
                let end = Scan.valueEnd(c, from: j)
                entries.append(Entry(key: key, lineStart: i, valueStart: start, valueEnd: end, lineEnd: skipToLineEnd(end)))
                i = skipToLineEnd(end)
            }
        }

        /// Past the value starting at `k`: a string, a list (across lines) or a bare word.
        static func valueEnd(_ c: [Character], from k: Int) -> Int {
            let n = c.count
            var k = k
            var depth = 0
            var lastSolid = k
            while k < n {
                let ch = c[k]
                if ch == "\"" || ch == "'" {
                    let triple = k + 2 < n && c[k + 1] == ch && c[k + 2] == ch
                    k += triple ? 3 : 1
                    while k < n {
                        if ch == "\"" && c[k] == "\\" { k += 2; continue }
                        if triple {
                            if c[k] == ch, k + 2 < n, c[k + 1] == ch, c[k + 2] == ch {
                                k += 3
                                while k < n, c[k] == ch { k += 1 }
                                break
                            }
                        } else if c[k] == ch || c[k].isNewline {
                            k += 1
                            break
                        }
                        k += 1
                    }
                    lastSolid = min(k, n)
                    if depth == 0 { return lastSolid }
                    continue
                }
                if ch == "[" { depth += 1; k += 1; lastSolid = k; continue }
                if ch == "]" {
                    depth -= 1
                    k += 1
                    lastSolid = k
                    if depth <= 0 { return k }
                    continue
                }
                if ch == "#" {
                    if depth == 0 { return lastSolid }
                    while k < n, !c[k].isNewline { k += 1 }
                    continue
                }
                if ch.isNewline {
                    if depth == 0 { return lastSolid }
                    k += 1
                    continue
                }
                k += 1
                if ch != " " && ch != "\t" { lastSolid = k }
            }
            return lastSolid
        }
    }
}

extension DenDenSettings {
    /// Writes one setting into the file at `url`, keeping everything else in
    /// it. A file that does not exist yet is started with a short header.
    public static func write(_ key: String, _ value: TOMLValue, to url: URL) throws {
        let fm = FileManager.default
        var text = ""
        if let data = fm.contents(atPath: url.path) {
            guard let existing = String(data: data, encoding: .utf8) else {
                throw TOMLError(line: 0, message: "denden.toml is not UTF-8 text")
            }
            text = existing
        } else {
            text = "# Den Den's settings. The Settings window writes here too; your comments stay.\n"
        }
        var updated = try TOMLEditor.setting(key, to: value, in: text)
        // `panel` replaces `builtin`, so the old key goes once the new one is written.
        if key == "panel" { updated = try TOMLEditor.removing("builtin", in: updated) }
        guard updated != text else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(updated.utf8).write(to: url, options: .atomic)
    }
}
