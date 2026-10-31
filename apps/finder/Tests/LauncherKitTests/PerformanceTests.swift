import XCTest
@testable import LauncherKit

/// UX rule: results under 100 ms per key. 10,000 rows through an instant
/// provider, the ranker and the grouping. Checked fully in release builds:
/// `swift test -c release -Xswiftc -enable-testing --filter LauncherKitTests.PerformanceTests`.
final class PerformanceTests: XCTestCase {
    static let words = ["alpha", "bravo", "cedar", "delta", "ember", "fjord", "harbor", "indigo", "juniper", "kestrel",
                        "lumen", "meadow", "nectar", "orbit", "pepper", "quartz", "raven", "saffron", "timber", "umber"]

    func catalogRows() -> [LaunchResult] {
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        return (0..<10_000).map { i in
            let title = "\(Self.words[next() % 20].capitalized) \(Self.words[next() % 20]) \(i)"
            return Make.row(title, id: "perf:\(i)", section: [.apps, .grandLine, .files, .snippets][i % 4], keywords: [Self.words[next() % 20]])
        }
    }

    func testTenThousandRowsRankWellUnderOneHundredMilliseconds() {
        let provider = CatalogProvider(id: "perf", title: "perf", symbol: "bolt", globalLimit: 10_000)
        provider.replace(catalogRows())
        let usage = UsageStore()
        for i in stride(from: 0, to: 2_000, by: 7) {
            usage.record(Make.row("x", id: "perf:\(i)"), query: LaunchQuery(raw: "ra"))
        }
        let engine = SearchEngine(providers: [provider], router: PrefixRouter(pathExists: { _ in false }), ranker: Ranker(usage: usage))

        #if DEBUG
        let limit = 1.5
        #else
        let limit = 0.05
        #endif
        for text in ["ra", "a", "saffron 12", "zz"] {
            let started = Date()
            let groups = engine.instantGroups(engine.plan(text))
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, limit, "\(text): \(Int(elapsed * 1000)) ms")
            if text == "ra" { XCTAssertFalse(groups.isEmpty) }
        }
    }
}
