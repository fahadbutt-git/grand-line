import XCTest
import IndexKit
@testable import LauncherKit

/// zoxide frecency, LaunchBar abbreviations, and the top row held while typing.
final class LearningTests: XCTestCase {
    let router = PrefixRouter(pathExists: { _ in false }, clipboardHistory: { false })

    func ranked(_ rows: [LaunchResult], _ text: String, usage: UsageStore) -> [String] {
        let query = router.parse(text)
        return Ranker(usage: usage).rank(Make.matched(rows, query.term), query: query).map(\.title)
    }

    // MARK: zoxide

    func testRecencyWeightsFollowZoxide() {
        XCTAssertEqual(UsageStore.recency(30), 4)
        XCTAssertEqual(UsageStore.recency(2 * 3_600), 2)
        XCTAssertEqual(UsageStore.recency(3 * 86_400), 0.5)
        XCTAssertEqual(UsageStore.recency(30 * 86_400), 0.25)
    }

    func testOlderPicksWeighLess() {
        let clock = Clock()
        let usage = UsageStore(now: { clock.now })
        usage.record(Make.row("Old"), query: router.parse("x"))
        clock.now += 10 * 86_400
        usage.record(Make.row("New"), query: router.parse("y"))
        let scores = usage.frecencies(for: router.parse(""))
        XCTAssertGreaterThan(scores["test:New"]!, scores["test:Old"]!)
        // 10 days at a 7-day half-life, then zoxide's ×¼ for more than a week.
        XCTAssertEqual(scores["test:Old"]!, pow(0.5, 10.0 / 7) * 0.25, accuracy: 1e-9)
    }

    // MARK: LaunchBar abbreviations

    func testFirstPickAssignsTheAbbreviation() {
        let usage = UsageStore()
        XCTAssertNil(usage.abbreviation(for: router.parse("vc")))
        usage.record(Make.row("Vector Cache"), query: router.parse("vc"))
        XCTAssertEqual(usage.abbreviation(for: router.parse("vc")), "test:Vector Cache")
        XCTAssertEqual(usage.abbreviation(for: router.parse("VC")), "test:Vector Cache", "folded like the query")
        XCTAssertNil(usage.abbreviation(for: router.parse("v")), "only exactly what was typed")
    }

    func testAnotherRowTakesOverAfterTwoPicksInARow() {
        let usage = UsageStore()
        let q = router.parse("vc")
        usage.record(Make.row("Vector Cache"), query: q)
        usage.record(Make.row("Visual Code"), query: q)
        XCTAssertEqual(usage.abbreviation(for: q), "test:Vector Cache", "one pick is not enough")
        usage.record(Make.row("Vector Cache"), query: q)
        usage.record(Make.row("Visual Code"), query: q)
        XCTAssertEqual(usage.abbreviation(for: q), "test:Vector Cache", "the run was broken")
        usage.record(Make.row("Visual Code"), query: q)
        XCTAssertEqual(usage.abbreviation(for: q), "test:Visual Code")
    }

    func testTheLearnedRowLeadsItsAbbreviation() {
        let usage = UsageStore()
        let rows = [Make.row("Visual Code"), Make.row("Vector Cache")]
        XCTAssertEqual(ranked(rows, "vc", usage: usage).first, "Visual Code")
        usage.record(Make.row("Vector Cache"), query: router.parse("vc"))
        XCTAssertEqual(ranked(rows, "vc", usage: usage).first, "Vector Cache")
    }

    func testTheLearnedRowNeverBeatsAnExactOrPrefixTitle() {
        let usage = UsageStore()
        for _ in 0..<5 { usage.record(Make.row("Vector Cache"), query: router.parse("vc")) }
        let rows = [Make.row("Vector Cache"), Make.row("Vcard")]
        XCTAssertEqual(ranked(rows, "vc", usage: usage), ["Vcard", "Vector Cache"])
    }

    func testFallbacksAreNeverLearned() {
        let usage = UsageStore()
        usage.record(Make.row("Search vc", fallback: true), query: router.parse("vc"))
        let rows = [Make.row("Search vc", fallback: true), Make.row("Vector Cache")]
        XCTAssertEqual(ranked(rows, "vc", usage: usage).first, "Vector Cache")
    }

    // MARK: Size

    func testPicksPerQueryAreCapped() {
        let usage = UsageStore()
        let q = router.parse("n")
        for i in 0..<30 { usage.record(Make.row("Note \(i)"), query: q) }
        XCTAssertLessThanOrEqual(usage.picks(for: q), UsageStore.maxPicksPerQuery)
        XCTAssertEqual(usage.picks(for: q), UsageStore.maxPicksPerQuery)
    }

    func testAbbreviationsAreCapped() {
        let usage = UsageStore()
        let row = Make.row("Notes")
        for i in 0..<(UsageStore.maxAbbreviations + 5) { usage.record(row, query: router.parse("q\(i)")) }
        XCTAssertEqual(usage.abbreviationCount, UsageStore.maxAbbreviations)
    }

    func testOlderUsageFilesStillLoadAndLearn() throws {
        let file = try Make.folder().appendingPathComponent("usage.json")
        try Make.write(#"{"global":{},"queries":{},"snapshots":{},"favourites":[]}"#, to: file)
        let usage = UsageStore(fileURL: file)
        XCTAssertNil(usage.abbreviation(for: router.parse("no")))
        usage.record(Make.row("Notes"), query: router.parse("no"))
        try usage.save()
        XCTAssertEqual(UsageStore(fileURL: file).abbreviation(for: router.parse("no")), "test:Notes")
    }

    func testForgetDropsTheAbbreviation() {
        let usage = UsageStore()
        usage.record(Make.row("Gone"), query: router.parse("go"))
        usage.forget("test:Gone")
        XCTAssertNil(usage.abbreviation(for: router.parse("go")))
    }

    // MARK: The top row while typing

    func row(_ id: String, tier: MatchTier, quality: Int, learned: Bool = false) -> LaunchResult {
        var r = Make.row(id, id: id)
        r.match = MatchInfo(title: tier, quality: quality)
        r.rank = RankKey(fallback: false, alias: .none, title: tier.rawValue, keyword: 5, frecency: 0, quality: quality, learned: learned)
        return r
    }

    func testTopRowStaysWhileTheQueryGrows() {
        var hold = TopRowHold()
        let first = hold.apply([row("A", tier: .prefix, quality: 50), row("B", tier: .prefix, quality: 40)], query: router.parse("a"))
        XCTAssertEqual(first.map(\.id), ["A", "B"])
        // B now scores higher, in the same tier: A stays on top.
        let second = hold.apply([row("B", tier: .prefix, quality: 60), row("A", tier: .prefix, quality: 50)], query: router.parse("ab"))
        XCTAssertEqual(second.map(\.id), ["A", "B"])
        XCTAssertEqual(hold.topID, "A")
    }

    func testAStrictlyBetterTierTakesTheTop() {
        var hold = TopRowHold()
        _ = hold.apply([row("A", tier: .prefix, quality: 50)], query: router.parse("ab"))
        let better = hold.apply([row("C", tier: .exact, quality: 10), row("A", tier: .prefix, quality: 50)], query: router.parse("abc"))
        XCTAssertEqual(better.first?.id, "C")
        let learned = hold.apply([row("L", tier: .prefix, quality: 1, learned: true), row("C", tier: .exact, quality: 10)],
                                 query: router.parse("abcd"))
        XCTAssertEqual(learned.first?.id, "L", "the row learned for exactly this abbreviation is a better tier")
    }

    func testDeletingOrRetypingStartsOver() {
        var hold = TopRowHold()
        _ = hold.apply([row("A", tier: .prefix, quality: 50), row("B", tier: .prefix, quality: 40)], query: router.parse("abc"))
        let shorter = hold.apply([row("B", tier: .prefix, quality: 60), row("A", tier: .prefix, quality: 50)], query: router.parse("ab"))
        XCTAssertEqual(shorter.first?.id, "B")
        let other = hold.apply([row("A", tier: .prefix, quality: 60), row("B", tier: .prefix, quality: 50)], query: router.parse("x"))
        XCTAssertEqual(other.first?.id, "A")
        _ = hold.apply([], query: router.parse(""))
        XCTAssertNil(hold.topID)
    }

    func testAHeldRowThatNoLongerMatchesIsDropped() {
        var hold = TopRowHold()
        _ = hold.apply([row("A", tier: .prefix, quality: 50)], query: router.parse("a"))
        let next = hold.apply([row("B", tier: .prefix, quality: 40)], query: router.parse("ab"))
        XCTAssertEqual(next.map(\.id), ["B"])
        XCTAssertEqual(hold.topID, "B")
    }

    func testEngineKeepsTheTopRowAcrossKeystrokes() {
        // "Notes" leads for "no"; for "not" a new row "Nota" would come first
        // (shorter title, same tier and score), but the row already on top stays.
        let provider = instant([Make.row("Notes"), Make.row("Notebook")])
        let engine = SearchEngine(providers: [provider], router: router)
        var hold = TopRowHold()
        let before = engine.instantGroups(engine.plan("no"), hold: &hold)
        XCTAssertEqual(before.first?.rows.first?.title, "Notes")
        provider.replace([Make.row("Nota"), Make.row("Notes"), Make.row("Notebook")])
        let fresh = engine.instantGroups(engine.plan("not"))
        XCTAssertEqual(fresh.first?.rows.first?.title, "Nota")
        let held = engine.instantGroups(engine.plan("not"), hold: &hold)
        XCTAssertEqual(held.first?.rows.first?.title, "Notes")
    }
}
