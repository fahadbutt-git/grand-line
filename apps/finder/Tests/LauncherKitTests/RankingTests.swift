import XCTest
@testable import LauncherKit

final class RankingTests: XCTestCase {
    let router = PrefixRouter(pathExists: { _ in false })

    func ranked(_ rows: [LaunchResult], _ text: String, ranker: Ranker = Ranker()) -> [String] {
        let query = router.parse(text)
        return ranker.rank(Make.matched(rows, query.term), query: query).map(\.title)
    }

    func testFixedOrderExactAliasThenAliasPrefixThenTitleThenKeyword() {
        let rows = [
            Make.row("Keyword only", keywords: ["term"]),
            Make.row("Term exact"),
            Make.row("Has prefix alias", aliases: ["termx"]),
            Make.row("Has exact alias", aliases: ["term"]),
        ]
        XCTAssertEqual(ranked(rows, "term"), ["Has exact alias", "Has prefix alias", "Term exact", "Keyword only"])
    }

    func testTitleTiersInOrder() {
        let rows = [Make.row("Visual Studio Code"), Make.row("Studio Notes"), Make.row("Studio"), Make.row("Mastudio")]
        XCTAssertEqual(ranked(rows, "studio"), ["Studio", "Studio Notes", "Visual Studio Code", "Mastudio"])
    }

    func testFallbacksAlwaysLast() {
        let rows = [Make.row("glaucoma search", fallback: true), Make.row("Glaucoma")]
        XCTAssertEqual(ranked(rows, "glaucoma"), ["Glaucoma", "glaucoma search"])
    }

    func testAliasTableBoostsItsTarget() {
        let table = AliasTable.parse("# alias\ttarget\nff\ttest:Firefox\n")
        let rows = [Make.row("Final Fantasy"), Make.row("Firefox")]
        XCTAssertEqual(ranked(rows, "ff", ranker: Ranker(aliases: table)), ["Firefox", "Final Fantasy"])
    }

    func testLearnedPicksBreakTiesForThatQuery() {
        let clock = Clock()
        let usage = UsageStore(now: { clock.now })
        let rows = [Make.row("Safari"), Make.row("Sage")]
        XCTAssertEqual(ranked(rows, "sa", ranker: Ranker(usage: usage)), ["Sage", "Safari"])
        usage.record(Make.row("Safari"), query: router.parse("sa"))
        XCTAssertEqual(ranked(rows, "sa", ranker: Ranker(usage: usage)), ["Safari", "Sage"])
    }

    func testLearningNeverJumpsATier() {
        let usage = UsageStore()
        for _ in 0..<20 { usage.record(Make.row("Visual Studio Code"), query: router.parse("code")) }
        let rows = [Make.row("Visual Studio Code"), Make.row("Code")]
        XCTAssertEqual(ranked(rows, "code", ranker: Ranker(usage: usage)).first, "Code")
    }

    func testPerQueryScoreOutweighsOtherQueries() {
        let usage = UsageStore()
        let q = router.parse("ma")
        usage.record(Make.row("Mail"), query: router.parse("mail"))
        usage.record(Make.row("Maps"), query: q)
        let scores = usage.frecencies(for: q)
        XCTAssertGreaterThan(scores["test:Maps"]!, scores["test:Mail"]!)
        // A longer query that starts with this one counts too.
        XCTAssertGreaterThan(scores["test:Mail"]!, 1)
    }

    func testScoresDecayByHalfLife() {
        let clock = Clock()
        let usage = UsageStore(halfLife: 100, now: { clock.now })
        usage.record(Make.row("A"), query: router.parse("a"))
        // Picked within the hour: zoxide's ×4.
        XCTAssertEqual(usage.frecency(id: "test:A", query: router.parse("")), 4, accuracy: 1e-9)
        clock.now += 100
        XCTAssertEqual(usage.frecency(id: "test:A", query: router.parse("")), 2, accuracy: 1e-9)
        usage.record(Make.row("A"), query: router.parse("a"))
        XCTAssertEqual(usage.frecency(id: "test:A", query: router.parse("")), 6, accuracy: 1e-9)
    }

    func testUsageSavesAndLoads() throws {
        let file = try Make.folder().appendingPathComponent("usage.json")
        let usage = UsageStore(fileURL: file)
        usage.record(Make.row("Notes"), query: router.parse("no"))
        usage.toggleFavourite(Make.row("Mail"))
        try usage.save()
        let again = UsageStore(fileURL: file)
        XCTAssertEqual(again.recents().map(\.title), ["Notes"])
        XCTAssertEqual(again.favourites().map(\.title), ["Mail"])
        XCTAssertTrue(again.isFavourite("test:Mail"))
        again.toggleFavourite(Make.row("Mail"))
        XCTAssertFalse(again.isFavourite("test:Mail"))
    }

    func testForgetRemovesEverywhere() {
        let usage = UsageStore()
        usage.record(Make.row("Gone"), query: router.parse("go"))
        usage.forget("test:Gone")
        XCTAssertTrue(usage.recents().isEmpty)
        XCTAssertEqual(usage.frecency(id: "test:Gone", query: router.parse("go")), 0)
    }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}
