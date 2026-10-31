import Foundation
import XCTest
@testable import LauncherKit

enum Make {
    static func row(_ title: String, id: String? = nil, section: ResultSection = .apps, keywords: [String] = [], aliases: [String] = [], fallback: Bool = false) -> LaunchResult {
        LaunchResult(
            id: id ?? "test:" + title,
            title: title,
            icon: .symbol("app"),
            section: section,
            keywords: keywords,
            aliases: aliases,
            actions: [LaunchAction("Open", symbol: "app", .open("/" + title))],
            isFallback: fallback,
            providerID: "test"
        )
    }

    /// Rows matched by a catalog, so they carry real match info.
    static func matched(_ rows: [LaunchResult], _ term: String) -> [LaunchResult] {
        Catalog(rows).search(term)
    }

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LauncherKitTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// 2026-10-31 12:00 in Toronto.
    static let noon: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!
    }()

    static let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()
}

/// A provider that answers later, or waits until it is cancelled.
struct SlowProvider: LaunchProvider {
    let id: String
    let title = "Slow"
    let symbol = "tortoise"
    let prefix: Prefix?
    let inGlobalSearch: Bool
    let rows: [LaunchResult]
    let delay: UInt64
    var keyword: String? = nil

    init(id: String = "slow", prefix: Prefix? = nil, inGlobalSearch: Bool = true, rows: [LaunchResult], delay: UInt64 = 20_000_000, keyword: String? = nil) {
        self.id = id
        self.prefix = prefix
        self.inGlobalSearch = inGlobalSearch
        self.rows = rows
        self.delay = delay
        self.keyword = keyword
    }

    func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        try await Task.sleep(nanoseconds: delay)
        return Catalog(rows).search(query.term)
    }
}

/// An instant provider over fixed rows.
func instant(_ rows: [LaunchResult], id: String = "fast", prefix: Prefix? = nil) -> CatalogProvider {
    let provider = CatalogProvider(id: id, title: id, symbol: "bolt", prefix: prefix)
    provider.replace(rows)
    return provider
}
