import Foundation

/// What Sight learns from what you pick: a decaying score per result, a
/// decaying score per result for each query you picked it from, the row each
/// abbreviation stands for, the rows to show as recents, and your favourites.
/// Saved as JSON in Application Support.
///
/// Frecency follows zoxide: the count-like score (which halves every half-life)
/// is multiplied by how recently the row was last picked: ×4 within the hour,
/// ×2 within the day, ×½ within the week, ×¼ after that.
///
/// Abbreviations follow LaunchBar: the first row picked after typing "xyz"
/// becomes what "xyz" stands for; picking a different row for "xyz" twice in a
/// row reassigns it.
public final class UsageStore: @unchecked Sendable {
    public struct Record: Codable, Equatable, Sendable {
        /// The score at `last`. It halves every half-life after that.
        public var score: Double
        public var last: Date
        public var count: Int
    }

    /// What one typed abbreviation stands for, and a row picked instead of it.
    public struct Abbreviation: Codable, Equatable, Sendable {
        public var id: String
        public var last: Date
        /// A different row picked for this abbreviation, and how many times in a row.
        public var challenger: String?
        public var challenges: Int
    }

    struct Stored: Codable {
        var global: [String: Record] = [:]
        var queries: [String: [String: Record]] = [:]
        var snapshots: [String: LaunchResult] = [:]
        var favourites: [String] = []
        var abbreviations: [String: Abbreviation] = [:]

        init() {}

        // Files written before abbreviations were learned have no such key.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            global = try c.decodeIfPresent([String: Record].self, forKey: .global) ?? [:]
            queries = try c.decodeIfPresent([String: [String: Record]].self, forKey: .queries) ?? [:]
            snapshots = try c.decodeIfPresent([String: LaunchResult].self, forKey: .snapshots) ?? [:]
            favourites = try c.decodeIfPresent([String].self, forKey: .favourites) ?? []
            abbreviations = try c.decodeIfPresent([String: Abbreviation].self, forKey: .abbreviations) ?? [:]
        }
    }

    public let halfLife: TimeInterval
    let fileURL: URL?
    let now: @Sendable () -> Date
    private let lock = NSLock()
    private var data = Stored()
    static let maxResults = 2_000
    static let maxQueries = 2_000
    /// Rows remembered per typed query; the weakest go first.
    static let maxPicksPerQuery = 12
    static let maxAbbreviations = 2_000
    /// Picks of a different row, in a row, that reassign an abbreviation.
    static let reassignAfter = 2

    public init(fileURL: URL? = nil, halfLife: TimeInterval = 7 * 86_400, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.halfLife = halfLife
        self.now = now
        if let fileURL, let raw = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            data = (try? decoder.decode(Stored.self, from: raw)) ?? Stored()
        }
    }

    func decayed(_ record: Record, at date: Date) -> Double {
        record.score * pow(0.5, max(0, date.timeIntervalSince(record.last)) / halfLife)
    }

    /// zoxide's weight for how long ago a row was last picked.
    public static func recency(_ age: TimeInterval) -> Double {
        switch age {
        case ..<3_600: return 4
        case ..<86_400: return 2
        case ..<(7 * 86_400): return 0.5
        default: return 0.25
        }
    }

    /// The decayed score times zoxide's recency weight.
    func frecency(_ record: Record, at date: Date) -> Double {
        decayed(record, at: date) * Self.recency(max(0, date.timeIntervalSince(record.last)))
    }

    func bumped(_ record: Record?, at date: Date) -> Record {
        guard let record else { return Record(score: 1, last: date, count: 1) }
        return Record(score: decayed(record, at: date) + 1, last: date, count: record.count + 1)
    }

    /// Forgets everything learned: scores, recents and favourites. The file
    /// is left to the caller (Settings moves it to the Trash first).
    public func reset() {
        lock.lock()
        data = Stored()
        lock.unlock()
    }

    public var fileLocation: URL? { fileURL }

    /// Records that `result` was run from `query`.
    public func record(_ result: LaunchResult, query: LaunchQuery) {
        let date = now()
        lock.lock()
        defer { lock.unlock() }
        data.global[result.id] = bumped(data.global[result.id], at: date)
        var snapshot = result
        snapshot.match = .unmatched
        snapshot.rank = .unranked
        data.snapshots[result.id] = snapshot
        let key = query.usageKey
        if !query.term.isEmpty {
            var picks = data.queries[key] ?? [:]
            picks[result.id] = bumped(picks[result.id], at: date)
            if picks.count > Self.maxPicksPerQuery {
                let weakest = picks.filter { $0.key != result.id }
                    .sorted { decayed($0.value, at: date) < decayed($1.value, at: date) }
                    .prefix(picks.count - Self.maxPicksPerQuery)
                for (id, _) in weakest { picks[id] = nil }
            }
            data.queries[key] = picks
            learn(key, picked: result.id, at: date)
        }
        prune(at: date)
    }

    /// LaunchBar's rule: the first pick assigns the abbreviation, the same
    /// pick confirms it, and a different row picked twice in a row takes it over.
    private func learn(_ key: String, picked id: String, at date: Date) {
        guard var entry = data.abbreviations[key] else {
            data.abbreviations[key] = Abbreviation(id: id, last: date, challenger: nil, challenges: 0)
            return
        }
        entry.last = date
        if entry.id == id {
            entry.challenger = nil
            entry.challenges = 0
        } else if entry.challenger == id {
            entry.challenges += 1
            if entry.challenges >= Self.reassignAfter {
                entry = Abbreviation(id: id, last: date, challenger: nil, challenges: 0)
            }
        } else {
            entry.challenger = id
            entry.challenges = 1
        }
        data.abbreviations[key] = entry
    }

    /// The row this exact query stands for, if one was learned.
    public func abbreviation(for query: LaunchQuery) -> String? {
        guard !query.term.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return data.abbreviations[query.usageKey]?.id
    }

    /// Learned scores for this query, by result id: picks from exactly this query
    /// count four times, picks from a longer query that starts with it twice, and
    /// every pick once. Computed once per search, not once per row.
    public func frecencies(for query: LaunchQuery) -> [String: Double] {
        let date = now()
        let key = query.usageKey
        lock.lock()
        defer { lock.unlock() }
        var scores: [String: Double] = [:]
        scores.reserveCapacity(data.global.count)
        for (id, record) in data.global { scores[id] = frecency(record, at: date) }
        guard !query.term.isEmpty else { return scores }
        for (typed, picks) in data.queries where typed.hasPrefix(key) {
            let weight: Double = typed == key ? 4 : 2
            for (id, record) in picks { scores[id, default: 0] += weight * frecency(record, at: date) }
        }
        return scores
    }

    public func frecency(id: String, query: LaunchQuery) -> Double {
        frecencies(for: query)[id] ?? 0
    }

    /// The rows picked most recently, newest first.
    public func recents(limit: Int = 9) -> [LaunchResult] {
        lock.lock()
        defer { lock.unlock() }
        let favourites = Set(data.favourites)
        return data.global
            .filter { !favourites.contains($0.key) && data.snapshots[$0.key] != nil }
            .sorted { $0.value.last > $1.value.last }
            .prefix(limit)
            .compactMap { data.snapshots[$0.key] }
    }

    public func favourites() -> [LaunchResult] {
        lock.lock()
        defer { lock.unlock() }
        return data.favourites.compactMap { data.snapshots[$0] }
    }

    public func isFavourite(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return data.favourites.contains(id)
    }

    public func toggleFavourite(_ result: LaunchResult) {
        lock.lock()
        defer { lock.unlock() }
        if let index = data.favourites.firstIndex(of: result.id) {
            data.favourites.remove(at: index)
        } else {
            var snapshot = result
            snapshot.match = .unmatched
            snapshot.rank = .unranked
            data.snapshots[result.id] = snapshot
            data.favourites.append(result.id)
        }
    }

    /// Forgets a result everywhere, for rows whose file is gone.
    public func forget(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        data.global[id] = nil
        data.snapshots[id] = nil
        data.favourites.removeAll { $0 == id }
        for key in Array(data.queries.keys) { data.queries[key]?[id] = nil }
        for (key, entry) in data.abbreviations where entry.id == id { data.abbreviations[key] = nil }
    }

    public func save() throws {
        guard let fileURL else { return }
        lock.lock()
        let copy = data
        lock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let raw = try encoder.encode(copy)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: fileURL, options: .atomic)
    }

    /// Keeps the store small: the weakest results and queries go first. Favourites stay.
    private func prune(at date: Date) {
        if data.global.count > Self.maxResults {
            let keep = Set(data.favourites)
            let weakest = data.global
                .filter { !keep.contains($0.key) }
                .sorted { decayed($0.value, at: date) < decayed($1.value, at: date) }
                .prefix(data.global.count - Self.maxResults)
            for (id, _) in weakest {
                data.global[id] = nil
                data.snapshots[id] = nil
            }
        }
        if data.queries.count > Self.maxQueries {
            let weakest = data.queries
                .map { key, picks in (key, picks.values.map(\.last).max() ?? .distantPast) }
                .sorted { $0.1 < $1.1 }
                .prefix(data.queries.count - Self.maxQueries)
            for (key, _) in weakest { data.queries[key] = nil }
        }
        if data.abbreviations.count > Self.maxAbbreviations {
            let oldest = data.abbreviations.sorted { $0.value.last < $1.value.last }
                .prefix(data.abbreviations.count - Self.maxAbbreviations)
            for (key, _) in oldest { data.abbreviations[key] = nil }
        }
    }

    /// How many rows are remembered for exactly this query.
    func picks(for query: LaunchQuery) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return data.queries[query.usageKey]?.count ?? 0
    }

    /// How many abbreviations are remembered (for tests and Settings).
    public var abbreviationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return data.abbreviations.count
    }
}
