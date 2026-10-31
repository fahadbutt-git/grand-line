import Foundation

extension Parser {
    mutating func filterNode(key rawKey: String, keyRange: Range<Int>, values raw: [RawValue], range: Range<Int>) -> Node? {
        let key = rawKey.lowercased()
        let values = raw.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        switch key {
        case "name": return textFilter(.name, key: key, values: values, range: range)
        case "text": return textFilter(.content, key: key, values: values, range: range)
        case "ext": return textFilter(.ext, key: key, values: values, range: range)
        case "from": return textFilter(.from, key: key, values: values, range: range)
        case "tag": return textFilter(.tag, key: key, values: values, range: range)
        case "author": return textFilter(.author, key: key, values: values, range: range)
        case "kind":
            return anyOf(values, key: key, range: range, failure: .badValue, message: { "Unknown kind “\($0)”" }) { value in
                FileKind(rawValue: value.text.lowercased()).map { Term.kind($0) }
            }
        case "in", "proj":
            return folderFilter(key: key, values: values, range: range)
        case "modified": return dateFilter(.modified, key: key, values: values, range: range)
        case "created": return dateFilter(.created, key: key, values: values, range: range)
        case "opened": return dateFilter(.opened, key: key, values: values, range: range)
        case "size":
            return anyOf(values, key: key, range: range, failure: .badSize, message: { "“\($0)” is not a size (try 5mb or >1gb)" }) { value in
                Comparison<Int64>.parse(value.text, value: ByteSize.parse).map { Term.size($0) }
            }
        case "pages":
            return anyOf(values, key: key, range: range, failure: .badValue, message: { "“\($0)” is not a page count" }) { value in
                Comparison<Int64>.parse(value.text, value: Parser.count).map { Term.pages($0) }
            }
        case "sort":
            guard values.count == 1, let order = SortKey(rawValue: values[0].text.lowercased()) else {
                report(.badValue, "Sort by modified, size or name", values.first?.range ?? range)
                return nil
            }
            sort = order
            return nil
        case "pdf": return Parser.withRest(.term(.kind(.pdf)), values)
        case "docx": return Parser.withRest(.term(.field(.ext, .word("docx"))), values)
        case "drive": return Parser.withRest(.term(.location(.googleDrive)), values)
        case "local": return Parser.withRest(.term(.location(.local)), values)
        default:
            report(.unknownFilter, "Unknown filter “\(rawKey):”", keyRange)
            return nil
        }
    }

    private mutating func textFilter(_ field: TextField, key: String, values: [RawValue], range: Range<Int>) -> Node? {
        anyOf(values, key: key, range: range, failure: .badValue, message: { "“\($0)” is not a valid value" }) { value in
            Pattern.parse(value.text, quoted: value.quoted).map { Term.field(field, $0) }
        }
    }

    private mutating func folderFilter(key: String, values: [RawValue], range: Range<Int>) -> Node? {
        anyOf(values, key: key, range: range, failure: .badValue, message: { "“\($0)” is not a folder" }) { value in
            Term.folder(value.text.trimmingCharacters(in: .whitespaces))
        }
    }

    private mutating func dateFilter(_ field: DateField, key: String, values: [RawValue], range: Range<Int>) -> Node? {
        anyOf(values, key: key, range: range, failure: .badDate, message: { "“\($0)” is not a date (try today, 30d, 2026-05)" }) { value in
            Comparison<DateSpec>.parse(value.text, value: DateSpec.parse).map { Term.date(field, $0) }
        }
    }

    private mutating func anyOf(
        _ values: [RawValue],
        key: String,
        range: Range<Int>,
        failure: QueryIssue.Kind,
        message: (String) -> String,
        _ make: (RawValue) -> Term?
    ) -> Node? {
        guard !values.isEmpty else {
            report(.badValue, "\(key): needs a value", range)
            return nil
        }
        var nodes: [Node] = []
        for value in values {
            if let term = make(value) {
                nodes.append(.term(term))
            } else {
                report(failure, message(value.text), value.range)
            }
        }
        return Parser.anyNode(nodes)
    }

    static func anyNode(_ nodes: [Node]) -> Node? {
        nodes.count <= 1 ? nodes.first : .or(nodes)
    }

    static func withRest(_ base: Node, _ values: [RawValue]) -> Node {
        var rest: [Node] = []
        for value in values {
            if let pattern = Pattern.parse(value.text, quoted: value.quoted) {
                rest.append(.term(.text(pattern)))
            }
        }
        guard let extra = anyNode(rest) else { return base }
        return .and([base, extra])
    }

    static func count(_ text: String) -> Int64? {
        guard isDigits(text) else { return nil }
        return Int64(text)
    }

    static func isDigits<S: StringProtocol>(_ text: S) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

extension Comparison {
    static func parse(_ text: String, value: (String) -> Value?) -> Comparison? {
        if let dots = text.range(of: "..") {
            guard let low = value(String(text[..<dots.lowerBound])),
                  let high = value(String(text[dots.upperBound...])) else { return nil }
            return .between(low, high)
        }
        let operators: [(String, (Value) -> Comparison)] = [
            (">=", Comparison.greaterOrEqual),
            ("<=", Comparison.lessOrEqual),
            (">", Comparison.greater),
            ("<", Comparison.less),
            ("=", Comparison.equal),
        ]
        for (symbol, make) in operators where text.hasPrefix(symbol) {
            return value(String(text.dropFirst(symbol.count))).map(make)
        }
        return value(text).map(Comparison.equal)
    }
}

extension DateSpec {
    static func parse(_ raw: String) -> DateSpec? {
        let text = raw.lowercased()
        switch text {
        case "today": return .today
        case "yesterday": return .yesterday
        case "week": return .daysAgo(7)
        case "month": return .daysAgo(30)
        case "year": return .daysAgo(365)
        default: break
        }
        if text.hasSuffix("d") {
            let number = text.dropLast()
            guard Parser.isDigits(number), let days = Int(number) else { return nil }
            return .daysAgo(days)
        }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ Parser.isDigits($0) }),
              parts[0].count == 4, let year = Int(parts[0]) else { return nil }
        if parts.count == 1 { return .year(year) }
        guard parts[1].count <= 2, let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        if parts.count == 2 { return .month(year: year, month: month) }
        guard parts[2].count <= 2, let day = Int(parts[2]),
              (1...DateSpec.daysIn(month: month, year: year)).contains(day) else { return nil }
        return .day(year: year, month: month, day: day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }
}

enum ByteSize {
    static func parse(_ raw: String) -> Int64? {
        let text = raw.lowercased()
        let units: [(String, Double)] = [("gb", 1e9), ("mb", 1e6), ("kb", 1e3), ("b", 1)]
        var number = Substring(text)
        var multiplier = 1.0
        for (suffix, factor) in units where text.hasSuffix(suffix) {
            number = text.dropLast(suffix.count)
            multiplier = factor
            break
        }
        guard !number.isEmpty,
              number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Double(number) else { return nil }
        return Int64((value * multiplier).rounded())
    }
}
