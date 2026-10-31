import Foundation

/// Answers the `=` prefix and sums typed anywhere: arithmetic, units, currency
/// (Bank of Canada rates, Canadian dollars by default), dates and time zones.
public struct Calculator: Sendable {
    public var rates: CurrencyRates?
    public var defaultCurrency: String
    public var dates: DateMath
    /// Sums, dates and time zones (Settings, Sources, Calculator).
    public var arithmetic = true
    /// Units and currency (Settings, Sources, Units and currency).
    public var conversions = true

    public init(rates: CurrencyRates? = nil, defaultCurrency: String = "CAD", dates: DateMath = DateMath()) {
        self.rates = rates
        self.defaultCurrency = defaultCurrency
        self.dates = dates
    }

    public struct Answer: Sendable, Equatable {
        /// What the row shows: "8.04672 km".
        public let value: String
        /// What Return copies: "8.04672".
        public let copy: String
        /// How the question was read: "5 mi in km".
        public let reading: String
    }

    /// - Parameter strict: for queries without the `=` prefix, a bare number is not a question.
    public func evaluate(_ input: String, strict: Bool = false) -> Answer? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if arithmetic, let answer = dates.evaluate(text) { return Answer(value: answer.text, copy: answer.copy, reading: text) }
        if conversions, let answer = conversion(text) { return answer }
        if conversions, let answer = money(text) { return answer }
        guard arithmetic, !strict || Expression.hasWork(text), let value = Expression.evaluate(text) else { return nil }
        return Answer(value: NumberText.grouped(value), copy: NumberText.plain(value), reading: text)
    }

    // MARK: Conversion

    static let joiners = [" in ", " to ", " as ", " -> ", " → ", " = "]

    func conversion(_ text: String) -> Answer? {
        let lower = text.lowercased()
        for joiner in Self.joiners {
            guard let range = lower.range(of: joiner, options: .backwards) else { continue }
            let left = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !left.isEmpty, !right.isEmpty, let pair = amountAndUnit(left) else { continue }
            let (amount, unit) = pair
            if let from = Units.named(unit), let to = Units.named(right), let value = Units.convert(amount, from: from, to: to) {
                let shown = NumberText.grouped(value)
                return Answer(value: "\(shown) \(to.symbol)", copy: NumberText.plain(value), reading: "\(NumberText.grouped(amount)) \(from.symbol) in \(to.symbol)")
            }
            if let from = currency(unit), let to = currency(right) { return exchange(amount, from: from, to: to) }
        }
        return nil
    }

    /// "100 usd", "€20", "$50": into the default currency, or from it into US dollars.
    func money(_ text: String) -> Answer? {
        guard let pair = amountAndUnit(text), let from = currency(pair.1) else { return nil }
        let amount = pair.0
        let to = from == defaultCurrency ? (defaultCurrency == "USD" ? "CAD" : "USD") : defaultCurrency
        return exchange(amount, from: from, to: to)
    }

    func exchange(_ amount: Double, from: String, to: String) -> Answer? {
        let reading = "\(NumberText.money(amount)) \(from) in \(to)"
        guard let rates else {
            return Answer(value: "Exchange rates are loading", copy: "", reading: reading)
        }
        guard let value = rates.convert(amount, from: from, to: to) else { return nil }
        return Answer(value: "\(NumberText.money(value)) \(to)", copy: NumberText.plain((value * 100).rounded() / 100), reading: reading + " · Bank of Canada, \(rates.date)")
    }

    /// An ISO code the rates know (or any code, before rates have loaded).
    func currency(_ word: String) -> String? {
        guard let code = CurrencyRates.code(for: word, defaultCurrency: defaultCurrency) else { return nil }
        if let rates { return rates.knows(code) ? code : nil }
        return ["USD", "EUR", "GBP", "JPY", "CAD", "AUD", "CHF", "INR", "CNY", "MXN"].contains(code) ? code : nil
    }

    static let symbolPrefixes = ["us$", "c$", "a$", "$", "€", "£", "¥", "₹"]

    /// Splits "5 km", "5km", "3 fl oz", "$20", "usd 20" or "2*3 kg" into the amount and the unit.
    func amountAndUnit(_ text: String) -> (Double, String)? {
        let lower = text.lowercased()
        for symbol in Self.symbolPrefixes where lower.hasPrefix(symbol) {
            guard let value = Expression.evaluate(String(text.dropFirst(symbol.count))) else { return nil }
            return (value, symbol)
        }
        let words = text.split(separator: " ").map(String.init)
        if words.count >= 2 {
            for take in [2, 1] where words.count > take {
                let unit = words.suffix(take).joined(separator: " ")
                guard Units.named(unit) != nil || currency(unit) != nil else { continue }
                if let value = Expression.evaluate(words.dropLast(take).joined(separator: " ")) { return (value, unit) }
            }
            if let code = currency(words[0]), let value = Expression.evaluate(words.dropFirst().joined(separator: " ")) {
                return (value, code)
            }
        }
        // Glued: "5km", "100°f", "3m/s".
        guard let start = text.lastIndex(where: { $0.isNumber || $0 == ")" }) else { return nil }
        let unit = String(text[text.index(after: start)...]).trimmingCharacters(in: .whitespaces)
        guard !unit.isEmpty, Units.named(unit) != nil || currency(unit) != nil,
              let value = Expression.evaluate(String(text[...start])) else { return nil }
        return (value, unit)
    }
}
