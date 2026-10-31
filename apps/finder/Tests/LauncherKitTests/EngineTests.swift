import XCTest
@testable import LauncherKit

final class EngineTests: XCTestCase {
    let router = PrefixRouter(pathExists: { _ in false })

    func collect(_ engine: SearchEngine, _ text: String) async -> [SearchUpdate] {
        var updates: [SearchUpdate] = []
        for await update in engine.search(text) { updates.append(update) }
        return updates
    }

    func testInstantResultsComeFirstAndSlowOnesMergeAfter() async {
        let engine = SearchEngine(providers: [
            SlowProvider(rows: [Make.row("Notes.txt", section: .files)]),
            instant([Make.row("Notes")]),
        ], router: router)
        let updates = await collect(engine, "notes")
        guard case .replace(let groups, _) = updates.first else { return XCTFail("no first batch") }
        XCTAssertEqual(groups.flatMap(\.rows).map(\.title), ["Notes"])
        guard case .merge(let late) = updates[1] else { return XCTFail("no merge") }
        XCTAssertEqual(late.map(\.title), ["Notes.txt"])
        guard case .finished = updates.last else { return XCTFail("not finished") }
    }

    func testPrefixRunsOnlyItsProvider() {
        let engine = SearchEngine(providers: [
            instant([Make.row("alpha one")], id: "a", prefix: .symbols),
            instant([Make.row("alpha two")], id: "b"),
        ], router: router)
        let plan = engine.plan(":alpha")
        XCTAssertEqual(plan.providers.map { $0.id }, ["a"])
        XCTAssertFalse(plan.topHit)
        XCTAssertEqual(engine.instantGroups(plan).flatMap(\.rows).map(\.title), ["alpha one"])
    }

    func testGlobalSkipsProvidersThatOptOut() {
        let engine = SearchEngine(providers: [
            SlowProvider(id: "windows", prefix: .windows, inGlobalSearch: false, rows: []),
            instant([Make.row("alpha")], id: "b"),
        ], router: router)
        XCTAssertEqual(engine.plan("alpha").providers.map { $0.id }, ["b"])
    }

    func testKeywordProviderRunsAloneWithTheRest() {
        let engine = SearchEngine(providers: [
            SlowProvider(id: "zot", inGlobalSearch: false, rows: [], keyword: "z"),
            instant([Make.row("z glaucoma")], id: "b"),
        ], router: router)
        let plan = engine.plan("z glaucoma")
        XCTAssertEqual(plan.providers.map { $0.id }, ["zot"])
        XCTAssertEqual(plan.query.term, "glaucoma")
    }

    func testPathsGoToThePathProvider() {
        let engine = SearchEngine(providers: [PathProvider(), instant([], id: "b")], router: router)
        XCTAssertEqual(engine.plan("~/Dri").providers.map { $0.id }, ["path"])
    }

    func testCancellingStopsSlowProviders() async {
        let engine = SearchEngine(providers: [SlowProvider(rows: [Make.row("never")], delay: 5_000_000_000)], router: router)
        let started = Date()
        let task = Task { () -> Int in
            var count = 0
            for await _ in engine.search("never") { count += 1 }
            return count
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let count = await task.value
        XCTAssertEqual(count, 1, "only the instant batch")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testEmptyQueryShowsFavouritesThenRecents() {
        let usage = UsageStore()
        usage.record(Make.row("Notes"), query: router.parse("no"))
        usage.toggleFavourite(Make.row("Mail"))
        let engine = SearchEngine(providers: [RecentsProvider(usage: usage), instant([Make.row("Notes")])], router: router)
        let groups = engine.instantGroups(engine.plan(""))
        XCTAssertEqual(groups.map(\.section), [.favourites, .recents])
        XCTAssertEqual(groups.map { $0.rows.map(\.title) }, [["Mail"], ["Notes"]])
    }
}
