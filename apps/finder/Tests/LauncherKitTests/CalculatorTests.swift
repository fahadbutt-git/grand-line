import XCTest
@testable import LauncherKit

final class CalculatorTests: XCTestCase {
    let rates = CurrencyRates(date: "2026-10-30", cadPer: ["USD": 1.4, "EUR": 1.5, "GBP": 1.75], fetched: Date(timeIntervalSince1970: 0))

    var calc: Calculator { Calculator(rates: rates, dates: DateMath(now: Make.noon, calendar: Make.toronto)) }

    func value(_ text: String, strict: Bool = false) -> String? { calc.evaluate(text, strict: strict)?.value }
    func copy(_ text: String) -> String? { calc.evaluate(text)?.copy }

    func testArithmetic() {
        XCTAssertEqual(value("2+3*4"), "14")
        XCTAssertEqual(value("(2+3)*4"), "20")
        XCTAssertEqual(value("2^10"), "1,024")
        XCTAssertEqual(value("-2^2"), "−4")
        XCTAssertEqual(value("7 mod 3"), "1")
        XCTAssertEqual(value("0.1+0.2"), "0.3")
        XCTAssertEqual(value("10 / 4"), "2.5")
        XCTAssertEqual(value("1,000,000 / 8"), "125,000")
        XCTAssertEqual(value("3 × 4 ÷ 2"), "6")
        XCTAssertEqual(value("sqrt(16) + 1"), "5")
        XCTAssertEqual(copy("pi"), "3.1415926536")
        XCTAssertNil(value("2 +"))
        XCTAssertNil(value("hello"))
    }

    func testPercentages() {
        XCTAssertEqual(value("20% of 150"), "30")
        XCTAssertEqual(value("150 + 10%"), "165")
        XCTAssertEqual(value("80 - 25%"), "60")
        XCTAssertEqual(value("50%"), "0.5")
    }

    func testStrictModeNeedsWork() {
        XCTAssertNil(value("2026", strict: true))
        XCTAssertEqual(value("2026", strict: false), "2,026")
        XCTAssertEqual(value("12*12", strict: true), "144")
    }

    func testUnits() {
        XCTAssertEqual(value("5 km in mi"), "3.1068559612 mi")
        XCTAssertEqual(value("5km to m"), "5,000 m")
        XCTAssertEqual(value("100 f in c"), "37.7777777778 °C")
        XCTAssertEqual(value("37 °C to °F"), "98.6 °F")
        XCTAssertEqual(value("12 in in cm"), "30.48 cm")
        XCTAssertEqual(value("21 mmHg in kPa"), "2.7997701357 kPa")
        XCTAssertEqual(value("2 cups in ml"), "473.176473 ml")
        XCTAssertEqual(value("1 GB in MB"), "1,000 MB")
        XCTAssertEqual(copy("3 ft in in"), "36")
        XCTAssertNil(value("5 km in kg"))
    }

    func testCurrencyDefaultsToCanadianDollars() {
        XCTAssertEqual(value("100 usd"), "140.00 CAD")
        XCTAssertEqual(value("$140"), "100.00 USD")
        XCTAssertEqual(value("100 usd in eur"), "93.33 EUR")
        XCTAssertEqual(value("€10 to gbp"), "8.57 GBP")
        XCTAssertEqual(copy("100 usd"), "140")
        XCTAssertTrue(calc.evaluate("100 usd")!.reading.contains("Bank of Canada, 2026-10-30"))
        XCTAssertNil(value("100 xyz"))
        let noRates = Calculator(rates: nil, dates: DateMath(now: Make.noon, calendar: Make.toronto))
        XCTAssertEqual(noRates.evaluate("100 usd")?.value, "Exchange rates are loading")
    }

    func testValetResponse() throws {
        let json = """
        {"observations": [
          {"d": "2026-10-29", "FXUSDCAD": {"v": "1.3900"}, "FXEURCAD": {"v": "1.5100"}},
          {"d": "2026-10-30", "FXUSDCAD": {"v": "1.3950"}}
        ]}
        """
        let parsed = try XCTUnwrap(CurrencyRates.parse(Data(json.utf8)))
        XCTAssertEqual(parsed.date, "2026-10-30")
        XCTAssertEqual(parsed.cadPer["USD"], 1.395)
        XCTAssertEqual(parsed.cadPer["EUR"], 1.51)
        XCTAssertEqual(parsed.cadPer["CAD"], 1)
        XCTAssertNil(CurrencyRates.parse(Data("{}".utf8)))
    }

    func testRatesAreCachedAndRefreshedWhenStale() async throws {
        let file = try Make.folder().appendingPathComponent("rates.json")
        let store = CurrencyRatesStore(fileURL: file, maxAge: 60)
        XCTAssertTrue(store.isStale())
        let body = Data(#"{"observations":[{"d":"2026-10-30","FXUSDCAD":{"v":"1.40"}}]}"#.utf8)
        await store.refreshIfStale(fetch: { _ in body })
        XCTAssertEqual(store.current?.cadPer["USD"], 1.4)
        XCTAssertFalse(store.isStale())
        XCTAssertEqual(CurrencyRatesStore(fileURL: file).current?.date, "2026-10-30")
        await store.refreshIfStale(fetch: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(store.current?.cadPer["USD"], 1.4, "a failed fetch keeps the old rates")
    }

    func testDates() {
        XCTAssertEqual(value("today"), "Sat, Oct 31, 2026 (today)")
        XCTAssertEqual(value("today + 30 days"), "Mon, Nov 30, 2026 (in 30 days · 4 weeks 2 days)")
        XCTAssertEqual(copy("today + 2 weeks"), "2026-11-14")
        XCTAssertEqual(copy("2026-12-25 - today"), "55")
        XCTAssertEqual(copy("days until dec 25"), "55")
        XCTAssertEqual(copy("days since 2026-10-01"), "30")
        XCTAssertEqual(copy("in 3 days"), "2026-11-03")
        XCTAssertEqual(copy("jan 1 - today"), "62", "a date without a year is the next one")
    }

    func testTimeZones() {
        XCTAssertEqual(value("3pm toronto in london"), "7:00 PM in London (Sat, Oct 31)")
        XCTAssertEqual(value("15:30 utc to est"), "11:30 AM in EST (Sat, Oct 31)")
        XCTAssertEqual(copy("noon in tokyo"), "1:00 AM")
        XCTAssertEqual(value("time in new york"), "12:00 PM in New York (Sat, Oct 31)")
        XCTAssertNotNil(value("vancouver time"))
        XCTAssertNil(DateMath.clock("15"))
        XCTAssertEqual(DateMath.clock("12am")?.hour, 0)
    }

    func testNumberText() {
        XCTAssertEqual(NumberText.grouped(1234567.891), "1,234,567.891")
        XCTAssertEqual(NumberText.plain(-0.0), "0")
        XCTAssertEqual(NumberText.plain(1e20), "1e20")
        XCTAssertEqual(NumberText.plain(0.00000001234), "1.234e-8")
        XCTAssertEqual(NumberText.money(5), "5.00")
        XCTAssertEqual(NumberText.money(1234.5), "1,234.50")
    }

    func testProviderRow() {
        let store = CurrencyRatesStore(fileURL: nil)
        store.set(rates)
        let provider = CalculatorProvider(rates: store, calendar: Make.toronto, now: { Make.noon })
        let row = provider.instantResults(for: LaunchQuery(raw: "2+2")).first
        XCTAssertEqual(row?.title, "4")
        XCTAssertEqual(row?.primary?.command, .copyText("4"))
        XCTAssertEqual(row?.match.title, .exact)
        XCTAssertTrue(provider.instantResults(for: LaunchQuery(raw: "42")).isEmpty)
        XCTAssertEqual(provider.instantResults(for: LaunchQuery(raw: "=42", prefix: .calculator, term: "42")).first?.title, "42")
    }
}
