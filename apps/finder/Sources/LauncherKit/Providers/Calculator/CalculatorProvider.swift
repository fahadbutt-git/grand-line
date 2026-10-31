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

    public init(rates: CurrencyRatesStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.rates = rates
        self.calendar = calendar
        self.now = now
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let calculator = Calculator(rates: rates.current, dates: DateMath(now: now(), calendar: calendar))
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
