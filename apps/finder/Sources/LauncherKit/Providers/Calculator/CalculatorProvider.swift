import Foundation

/// The calculator as a row: the answer on top, Return copies it.
public final class CalculatorProvider: InstantProvider, @unchecked Sendable {
    public let id = "calculator"
    public let title = "Calculator"
    public let symbol = "equal.square"
    public let prefix: Prefix? = .calculator
    public let inGlobalSearch = true
    let rates: CurrencyRatesStore
    let now: @Sendable () -> Date
    let calendar: Calendar
    let arithmetic: Bool
    let conversions: Bool

    public init(rates: CurrencyRatesStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() },
                arithmetic: Bool = true, conversions: Bool = true) {
        self.rates = rates
        self.calendar = calendar
        self.now = now
        self.arithmetic = arithmetic
        self.conversions = conversions
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        var calculator = Calculator(rates: rates.current, dates: DateMath(now: now(), calendar: calendar))
        calculator.arithmetic = arithmetic
        calculator.conversions = conversions
        guard let answer = calculator.evaluate(query.term, strict: query.prefix != .calculator) else { return [] }
        var actions: [LaunchAction] = []
        if !answer.copy.isEmpty {
            actions.append(LaunchAction("Copy answer", symbol: "doc.on.doc", .copyText(answer.copy)))
            actions.append(LaunchAction("Paste answer", symbol: "doc.on.clipboard", .paste(answer.copy)))
            actions.append(LaunchAction("Copy with unit", symbol: "textformat", .copyText(answer.value)))
        }
        return [LaunchResult(
            id: "calc",
            title: answer.value,
            subtitle: answer.reading,
            icon: .symbol("equal.square"),
            section: .answers,
            actions: actions,
            providerID: id,
            match: .answer
        )]
    }
}
