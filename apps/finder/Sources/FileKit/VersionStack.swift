import Foundation

/// Versions of one document stacked under the newest: "Report v01.docx",
/// "Report v02.docx", "Report final.docx", "Report final2.docx", "Report copy.docx",
/// "Report (1).docx" and "Report 2026-10-31.docx" are one stack.
public struct VersionStack: Sendable, Equatable {
    /// The most recently modified version.
    public let newest: URL
    /// The other versions, newest first.
    public let older: [URL]

    public var all: [URL] { [newest] + older }

    /// Groups items in the same folder that share a family name. Items without
    /// other versions come back as stacks of one, in the order given.
    public static func stacks(for items: [(url: URL, modified: Date)]) -> [VersionStack] {
        var order: [String] = []
        var groups: [String: [(url: URL, modified: Date, position: Int)]] = [:]
        for (position, item) in items.enumerated() {
            let key = item.url.deletingLastPathComponent().standardizedFileURL.path + "/" + family(of: item.url.lastPathComponent)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append((item.url, item.modified, position))
        }
        return order.map { key in
            let sorted = groups[key]!.sorted {
                $0.modified != $1.modified ? $0.modified > $1.modified : $0.position > $1.position
            }
            return VersionStack(newest: sorted[0].url, older: sorted.dropFirst().map { $0.url })
        }
    }

    /// Reads modification dates from disk.
    public static func stacks(for urls: [URL]) -> [VersionStack] {
        stacks(for: urls.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (url: url, modified: date)
        })
    }

    /// The name with version marks removed, lowercased: "Report v02 final.docx" is "report.docx".
    public static func family(of name: String) -> String {
        let ext = (name as NSString).pathExtension
        var stem = (name as NSString).deletingPathExtension
        if stem.isEmpty || ext.contains(" ") { stem = name }
        let suffix = stem == name || ext.isEmpty ? "" : "." + ext.lowercased()
        var current = stem.lowercased()
        var changed = true
        while changed {
            changed = false
            for strip in [stripCount, stripCopy, stripFinal, stripVersion, stripTrailingDate, stripLeadingDate] {
                if let shorter = strip(current), !shorter.isEmpty, shorter != current {
                    current = shorter
                    changed = true
                }
            }
        }
        return current + suffix
    }

    // MARK: Marks

    static func isSeparator(_ c: Character) -> Bool { c == " " || c == "_" || c == "-" || c == "." }
    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func trimmed(_ text: Substring) -> String {
        var text = text
        while let last = text.last, isSeparator(last) { text = text.dropLast() }
        while let first = text.first, isSeparator(first) { text = text.dropFirst() }
        return String(text)
    }

    /// "report (1)" and "report(2)".
    static func stripCount(_ s: String) -> String? {
        guard s.hasSuffix(")"), let open = s.lastIndex(of: "(") else { return nil }
        let inside = s[s.index(after: open)..<s.index(before: s.endIndex)]
        guard !inside.isEmpty, inside.allSatisfy(isDigit) else { return nil }
        return trimmed(s[..<open])
    }

    /// "report copy" and "report copy 2".
    static func stripCopy(_ s: String) -> String? {
        stripWord("copy", from: s, numbered: true)
    }

    /// "report final", "report_final2", "report-FINAL".
    static func stripFinal(_ s: String) -> String? {
        stripWord("final", from: s, numbered: true)
    }

    /// "report v2", "report_v01", "report-V3".
    static func stripVersion(_ s: String) -> String? {
        let digits = s.reversed().prefix(while: isDigit).count
        guard digits > 0 else { return nil }
        let body = s.dropLast(digits)
        guard body.hasSuffix("v") else { return nil }
        let before = body.dropLast()
        guard before.isEmpty || isSeparator(before.last!) else { return nil }
        return trimmed(before)
    }

    /// "report 2026-10-31", "report_20261031", "report 2026.10.31".
    static func stripTrailingDate(_ s: String) -> String? {
        for length in [10, 8] where s.count >= length {
            let tail = s.suffix(length)
            let before = s.dropLast(length)
            if isDate(tail), before.isEmpty || isSeparator(before.last!) { return trimmed(before) }
        }
        return nil
    }

    /// "2026-10-31 report".
    static func stripLeadingDate(_ s: String) -> String? {
        for length in [10, 8] where s.count > length {
            let head = s.prefix(length)
            let after = s.dropFirst(length)
            if isDate(head), let next = after.first, isSeparator(next) { return trimmed(after) }
        }
        return nil
    }

    static func stripWord(_ word: String, from s: String, numbered: Bool) -> String? {
        var body = Substring(s)
        if numbered {
            let digits = body.reversed().prefix(while: isDigit).count
            if digits > 0 {
                body = body.dropLast(digits)
                if let last = body.last, isSeparator(last) { body = body.dropLast() }
            }
        }
        guard body.hasSuffix(word) else { return nil }
        let before = body.dropLast(word.count)
        guard before.isEmpty || isSeparator(before.last!) else { return nil }
        return trimmed(before)
    }

    /// yyyy-mm-dd with -, _ or . between, or yyyymmdd.
    static func isDate(_ text: Substring) -> Bool {
        let chars = Array(text)
        let digits: [Character]
        if chars.count == 10 {
            let separator = chars[4]
            guard "-_.".contains(separator), chars[7] == separator else { return false }
            digits = Array(chars[0..<4] + chars[5..<7] + chars[8..<10])
        } else if chars.count == 8 {
            digits = chars
        } else {
            return false
        }
        guard digits.allSatisfy(isDigit),
              let year = Int(String(digits[0..<4])), let month = Int(String(digits[4..<6])),
              let day = Int(String(digits[6..<8])) else { return false }
        return (1990...2100).contains(year) && (1...12).contains(month) && (1...31).contains(day)
    }
}
