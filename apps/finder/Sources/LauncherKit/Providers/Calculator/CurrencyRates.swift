import Foundation

/// Daily exchange rates from the Bank of Canada's Valet API, as Canadian
/// dollars per unit of each currency.
public struct CurrencyRates: Codable, Sendable, Equatable {
    /// The observation date, "2026-10-30".
    public var date: String
    public var cadPer: [String: Double]
    public var fetched: Date

    public static let url = URL(string: "https://www.bankofcanada.ca/valet/observations/group/FX_RATES_DAILY/json?recent=5")!

    public init(date: String, cadPer: [String: Double], fetched: Date) {
        self.date = date
        var rates = cadPer
        rates["CAD"] = 1
        self.cadPer = rates
        self.fetched = fetched
    }

    /// Reads a Valet response: {"observations":[{"d":"…","FXUSDCAD":{"v":"1.39"},…}]}.
    /// The newest value of each series wins, since a holiday can skip one.
    public static func parse(_ data: Data, fetched: Date = Date()) -> CurrencyRates? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let observations = json["observations"] as? [[String: Any]] else { return nil }
        var rates: [String: Double] = [:]
        var latest = ""
        for observation in observations.sorted(by: { ($0["d"] as? String ?? "") < ($1["d"] as? String ?? "") }) {
            if let d = observation["d"] as? String { latest = max(latest, d) }
            for (key, value) in observation where key.hasPrefix("FX") && key.hasSuffix("CAD") && key.count == 8 {
                let code = String(key.dropFirst(2).prefix(3))
                if let entry = value as? [String: Any], let text = entry["v"] as? String, let rate = Double(text), rate > 0 {
                    rates[code] = rate
                }
            }
        }
        guard !rates.isEmpty else { return nil }
        return CurrencyRates(date: latest, cadPer: rates, fetched: fetched)
    }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = cadPer[from.uppercased()], let b = cadPer[to.uppercased()] else { return nil }
        return amount * a / b
    }

    public func knows(_ code: String) -> Bool { cadPer[code.uppercased()] != nil }

    /// Currency symbols and names people type, to ISO codes. "$" is the default currency.
    public static func code(for word: String, defaultCurrency: String) -> String? {
        switch word.lowercased() {
        case "$", "dollar", "dollars": return defaultCurrency
        case "c$", "cad$": return "CAD"
        case "us$", "usd$": return "USD"
        case "€", "euro", "euros": return "EUR"
        case "£", "pound sterling", "quid": return "GBP"
        case "¥", "yen": return "JPY"
        case "₹", "rupee", "rupees": return "INR"
        case "a$": return "AUD"
        case "fr", "chf": return "CHF"
        default:
            let upper = word.uppercased()
            return upper.count == 3 && upper.allSatisfy(\.isLetter) ? upper : nil
        }
    }
}

/// Keeps the rates on disk and fetches new ones when they are over 12 hours old.
public final class CurrencyRatesStore: @unchecked Sendable {
    let fileURL: URL?
    let maxAge: TimeInterval
    private let lock = NSLock()
    private var rates: CurrencyRates?
    private var fetching = false

    public init(fileURL: URL?, maxAge: TimeInterval = 12 * 3_600) {
        self.fileURL = fileURL
        self.maxAge = maxAge
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            rates = try? decoder.decode(CurrencyRates.self, from: data)
        }
    }

    public var current: CurrencyRates? {
        lock.lock()
        defer { lock.unlock() }
        return rates
    }

    public func set(_ fresh: CurrencyRates) {
        lock.lock()
        rates = fresh
        lock.unlock()
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(fresh) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func isStale(now: Date = Date()) -> Bool {
        guard let fetched = current?.fetched else { return true }
        return now.timeIntervalSince(fetched) > maxAge
    }

    private func beginFetch() -> Bool {
        lock.withLock {
            if fetching { return false }
            fetching = true
            return true
        }
    }

    private func endFetch() {
        lock.withLock { fetching = false }
    }

    /// Fetches once at a time; failures keep the old rates.
    public func refreshIfStale(now: Date = Date(), fetch: @escaping @Sendable (URL) async throws -> Data) async {
        guard isStale(now: now), beginFetch() else { return }
        defer { endFetch() }
        guard let data = try? await fetch(CurrencyRates.url), let fresh = CurrencyRates.parse(data, fetched: now) else { return }
        set(fresh)
    }
}
