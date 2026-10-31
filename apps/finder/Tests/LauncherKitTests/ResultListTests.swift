import XCTest
@testable import LauncherKit

final class ResultListTests: XCTestCase {
    let query = LaunchQuery(raw: "no", term: "no")

    func rank(_ rows: [LaunchResult]) -> [LaunchResult] {
        Ranker().rank(Make.matched(rows, query.term), query: query)
    }

    func testTopHitThenSectionsInFixedOrder() {
        let rows = rank([
            Make.row("Notes web", section: .web),
            Make.row("Notes.txt", section: .files),
            Make.row("Notes", section: .apps),
            Make.row("Notebook", section: .grandLine),
        ])
        let groups = ResultGrouping.group(rows)
        XCTAssertEqual(groups.map(\.section), [.topHit, .grandLine, .files, .web])
        XCTAssertEqual(groups[0].rows.map(\.title), ["Notes"])
    }

    func testSectionLimits() {
        let rows = rank((1...20).map { Make.row("Note \($0)", section: .apps) })
        let groups = ResultGrouping.group(rows)
        XCTAssertEqual(groups[1].rows.count, ResultSection.apps.limit)
        XCTAssertEqual(ResultGrouping.group(rows, topHit: false, limitScale: 2)[0].rows.count, 2 * ResultSection.apps.limit)
    }

    func testFallbackIsNeverTopHit() {
        let groups = ResultGrouping.group(rank([Make.row("no results", section: .web, fallback: true)]))
        XCTAssertEqual(groups.map(\.section), [.web])
    }

    func testCommandNumbersRunTheNthRow() {
        let list = ResultList(groups: ResultGrouping.group(rank((1...12).map { Make.row("Note \($0)", section: $0 % 2 == 0 ? .apps : .files) })))
        XCTAssertEqual(list.row(shortcut: 1)?.id, list.rows[0].id)
        XCTAssertEqual(list.row(shortcut: 9)?.id, list.rows[8].id)
        XCTAssertNil(list.row(shortcut: 10))
        XCTAssertEqual(list.shortcutNumber(of: list.rows[2].id), 3)
    }

    func testSelectionMovesWithinBounds() {
        var list = ResultList(groups: ResultGrouping.group(rank([Make.row("Note a"), Make.row("Note b")])))
        XCTAssertEqual(list.selectedIndex, 0)
        list.moveSelection(by: -1)
        XCTAssertEqual(list.selectedIndex, 0)
        list.moveSelection(by: 5)
        XCTAssertEqual(list.selectedIndex, 1)
    }

    func testAsyncResultsNeverStealTheSelection() {
        var list = ResultList(groups: ResultGrouping.group(rank([Make.row("Notes", section: .apps), Make.row("Notebook", section: .apps)])))
        let top = list.selected!.id
        // A better match arrives late: it may not become the top hit.
        list.merge(rank([Make.row("No", section: .files), Make.row("Nova", section: .apps)]))
        XCTAssertEqual(list.selected?.id, top)
        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(list.groups[0].section, .topHit)
        XCTAssertEqual(list.groups[0].rows.map(\.title), ["Notes"])
        XCTAssertTrue(list.rows.contains { $0.title == "No" })
    }

    func testRowsAtOrAboveTheSelectionStayPut() {
        var list = ResultList(groups: ResultGrouping.group(rank([
            Make.row("Notes", section: .apps), Make.row("Notebook", section: .apps), Make.row("Nobody", section: .apps),
        ])))
        list.moveSelection(by: 2)
        let before = Array(list.rows.prefix(3).map(\.id))
        list.merge(rank([Make.row("Nod", section: .apps)]))
        XCTAssertEqual(Array(list.rows.prefix(3).map(\.id)), before)
        XCTAssertEqual(list.selectedIndex, 2)
        XCTAssertEqual(list.rows.last?.title, "Nod")
    }

    func testANewSectionAboveTheSelectionKeepsTheSelectedRow() {
        var list = ResultList(groups: ResultGrouping.group(rank([Make.row("Notes", section: .apps), Make.row("Notes.txt", section: .files)])))
        list.moveSelection(by: 1)
        let selected = list.selected!.id
        list.merge(rank([Make.row("Note cmd", section: .grandLine)]))
        XCTAssertEqual(list.selected?.id, selected)
        XCTAssertEqual(list.groups.map(\.section), [.topHit, .grandLine, .files])
    }

    func testDuplicatesAreIgnoredAndShownRowsNeverDisappear() {
        var list = ResultList(groups: ResultGrouping.group(rank([Make.row("Notes"), Make.row("Notebook")])))
        let count = list.rows.count
        list.merge(rank([Make.row("Notes")]))
        XCTAssertEqual(list.rows.count, count)
    }

    func testMergeIntoAnEmptyListActsAsReplace() {
        var list = ResultList()
        list.merge(rank([Make.row("Notes")]))
        XCTAssertEqual(list.selected?.title, "Notes")
        XCTAssertEqual(list.groups.first?.section, .topHit)
    }
}
