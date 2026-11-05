import Foundation
import IndexKit
import XCTest
@testable import BrowserKit

/// Search results in relevance order: name matches first, best first, then
/// files found only by what is inside them, under their own header, and a
/// status bar that says which is which. Folders keep their own sorts.
final class RelevanceTests: XCTestCase {
    let downloads = "/Users/me/Downloads"
    let day: TimeInterval = 86_400
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: The sort

    func testRelevanceIsOfferedOnlyForSearchResults() {
        XCTAssertFalse(SortField.folderFields.contains(.relevance))
        XCTAssertEqual(SortField.offered(searching: true).first, .relevance)
        XCTAssertEqual(SortField.offered(searching: false), SortField.folderFields)
        XCTAssertEqual(SortField.relevance.title, "Relevance")
        XCTAssertEqual(ItemSort.relevance.field, .relevance)
        XCTAssertEqual(ItemSort(field: .relevance, foldersFirst: true, grouping: .kind).forFolder,
                       ItemSort(field: .name, foldersFirst: true, grouping: .kind), "a folder shows it as Name")
        XCTAssertEqual(ItemSort(field: .modified).forFolder, ItemSort(field: .modified))
    }

    func testViewSettingsStillDecodeAndRelevanceRoundTrips() throws {
        let old = #"{"mode":"list","sort":{"field":"name","ascending":true},"iconSize":64}"#
        XCTAssertEqual(try JSONDecoder().decode(ViewSettings.self, from: Data(old.utf8)).sort, ItemSort(field: .name))
        let dated = #"{"field":"modified","ascending":false,"foldersFirst":true,"grouping":"kind"}"#
        XCTAssertEqual(try JSONDecoder().decode(ItemSort.self, from: Data(dated.utf8)),
                       ItemSort(field: .modified, ascending: false, foldersFirst: true, grouping: .kind))
        let unknown = #"{"field":"someday","ascending":true}"#
        XCTAssertEqual(try JSONDecoder().decode(ItemSort.self, from: Data(unknown.utf8)).field, .name, "a newer version's sort loads as Name")
        let relevance = try JSONEncoder().encode(ItemSort.relevance)
        XCTAssertEqual(try JSONDecoder().decode(ItemSort.self, from: relevance), .relevance)
    }

    func testClickingAHeaderLeavesRelevanceAndChoosingRelevanceReturns() {
        let byName = ItemSort.relevance.clicking(.name)
        XCTAssertEqual(byName.field, .name)
        XCTAssertTrue(byName.ascending)
        XCTAssertEqual(byName.choosing(.relevance), .relevance)
    }

    /// The owner's case: "conj" in Downloads. Name matches lead, the best tier
    /// first and the newest within it; Spotlight's other name matches next;
    /// files found only inside last, newest first. Sorted by name, the same
    /// rows put 0.png and 00_Abstract.docx at the top.
    func testRelevanceOrder() {
        let rows = [
            item("_19_V2_Testing_Match_testing.docx", modified: now - 1 * day, in: downloads),
            item("00_Abstract.docx", modified: now - 30 * day, in: downloads),
            item("0.png", modified: now - 2 * day, in: downloads),
            item("Conj Flap", folder: true, modified: now - 90 * day, in: downloads),
            item("conj notes.txt", modified: now - 3 * day, in: downloads),
            item("Lid Study - CONJ", folder: true, modified: now - 10 * day, in: downloads),
            item("K1. Conjunctivitis in the First Month of Life.pdf", modified: now - 5 * day, in: downloads),
            item("old conj.txt", modified: now - 400 * day, in: downloads),
        ]
        let ranks: [String: SearchRank] = [
            path("Conj Flap"): SearchRank(source: .nameIndex, tier: .prefix),
            path("conj notes.txt"): SearchRank(source: .nameIndex, tier: .prefix),
            path("Lid Study - CONJ"): SearchRank(source: .nameIndex, tier: .wordStart),
            path("K1. Conjunctivitis in the First Month of Life.pdf"): SearchRank(source: .nameIndex, tier: .wordStart),
            path("old conj.txt"): SearchRank(source: .nameSpotlight),
            path("_19_V2_Testing_Match_testing.docx"): SearchRank(source: .content),
            path("00_Abstract.docx"): SearchRank(source: .content),
            path("0.png"): SearchRank(source: .content),
        ]
        let sorted = ItemSorter.sorted(rows, by: .relevance, ranks: ranks).map(\.name)
        XCTAssertEqual(sorted, [
            "conj notes.txt", "Conj Flap",
            "K1. Conjunctivitis in the First Month of Life.pdf", "Lid Study - CONJ",
            "old conj.txt",
            "_19_V2_Testing_Match_testing.docx", "0.png", "00_Abstract.docx",
        ])
        XCTAssertEqual(ItemSorter.sorted(rows, by: ItemSort(field: .name), ranks: ranks).first?.name, "_19_V2_Testing_Match_testing.docx",
                       "a header click still sorts by the column")
        XCTAssertEqual(ItemSorter.sorted(rows, by: .relevance).map(\.name), rows.map(\.name), "without ranks the order stays")
        XCTAssertEqual(ItemSorter.sorted(rows, by: ItemSort(field: .relevance, foldersFirst: true), ranks: ranks).first?.name, "conj notes.txt",
                       "the best match leads even with Keep Folders on Top")
    }

    // MARK: Merging the sources

    func testCombineKeepsHowEachWasFound() {
        let plan = SearchPlan.make("conj", scope: .folder(downloads), home: home.path, drives: [])
        let index = [
            IndexMatch(path: path("Conj Flap"), name: "Conj Flap", isFolder: true, tier: .prefix, highlights: []),
            IndexMatch(path: path("Lid Study - CONJ"), name: "Lid Study - CONJ", isFolder: true, tier: .wordStart, highlights: []),
        ]
        let spotlight = [path("0.png"), path("Conj Flap"), path("old conj.txt"), path("00_Abstract.docx"),
                         "/Users/me/Downloads/.cache/conj-cache.db"]
        let hits = SearchResults.combine(index: index, spotlight: spotlight, plan: plan)
        XCTAssertEqual(hits.paths, [path("Conj Flap"), path("Lid Study - CONJ"), path("old conj.txt"), path("0.png"), path("00_Abstract.docx")])
        XCTAssertEqual(hits.ranks[path("Conj Flap")], SearchRank(source: .nameIndex, tier: .prefix))
        XCTAssertEqual(hits.ranks[path("old conj.txt")]?.source, .nameSpotlight)
        XCTAssertEqual(hits.ranks[path("0.png")]?.source, .content)
        XCTAssertEqual(hits.nameCount, 3)
        XCTAssertEqual(hits.insideFileCount, 2)
    }

    func testTheLimitCutsInsideFileMatchesFirst() {
        let plan = SearchPlan.make("conj", scope: .folder(downloads), home: home.path, drives: [])
        let content = (0..<50).map { path("file \($0).docx") }
        let index = [IndexMatch(path: path("conj notes.txt"), name: "conj notes.txt", isFolder: false, tier: .prefix, highlights: [])]
        let hits = SearchResults.combine(index: index, spotlight: content + [path("conj late.txt")], plan: plan, limit: 10)
        XCTAssertEqual(hits.paths.count, 10)
        XCTAssertEqual(Array(hits.paths.prefix(2)), [path("conj notes.txt"), path("conj late.txt")],
                       "a Spotlight name match Spotlight listed last still comes before the files found inside")
    }

    func testWithoutContentNothingIsClassedInsideFiles() {
        let plan = SearchPlan.make("conj", scope: .folder(downloads), home: home.path, drives: [], content: false)
        XCTAssertFalse(plan.searchesContent)
        XCTAssertEqual(plan.predicate.predicateFormat, "kMDItemFSName CONTAINS[cd] \"conj\"")
        // "conj kind:pdf" with content matches off: names only, through Spotlight.
        let filtered = SearchPlan.make("conj kind:pdf", scope: .folder(downloads), home: home.path, drives: [], content: false)
        XCTAssertNil(filtered.nameText)
        XCTAssertFalse(filtered.predicate.predicateFormat.contains("kMDItemTextContent"))
    }

    func testWhatCountsAsFoundByName() {
        let plan = SearchPlan.make("conj kind:pdf", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(plan.matchesName("/Users/me/K1. Conjunctivitis.pdf"))
        XCTAssertFalse(plan.matchesName("/Users/me/0.pdf"))
        let either = SearchPlan.make("(conj OR lid)", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(either.matchesName("/Users/me/Lid Study.docx"))
        XCTAssertFalse(either.matchesName("/Users/me/00_Abstract.docx"))
        let text = SearchPlan.make("text:conj", scope: .home, home: home.path, drives: [])
        XCTAssertFalse(text.matchesName("/Users/me/conj notes.txt"), "text: asks for what is inside")
        let prefix = SearchPlan.make("conj*", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(prefix.matchesName("/Users/me/Conjunctiva.pdf"))
        XCTAssertFalse(prefix.matchesName("/Users/me/Lid Study - CONJ"), "conj* is the start of the name")
        let kinds = SearchPlan.make("kind:pdf", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(kinds.matchesName("/Users/me/anything.pdf"), "a filter alone never looks inside")
    }

    func testSavedSearchesSearchNamesToo() {
        let saved: (String) -> String? = { $0 == "lids" ? "conj" : nil }
        let plan = SearchPlan.make("@lids", scope: .home, home: home.path, drives: [], savedSearch: saved)
        XCTAssertEqual(plan.nameText, "conj", "a saved search of words also searches the name index")
        XCTAssertEqual(plan.words, ["conj"])
        XCTAssertTrue(plan.searchesContent)
        XCTAssertFalse(plan.matchesName("/Users/me/00_Abstract.docx"), "its content matches are told apart")
        XCTAssertTrue(plan.matchesName("/Users/me/Conj Flap"))
        XCTAssertTrue(SearchPlan.make("@missing", scope: .home, home: home.path, drives: [], savedSearch: saved).isUnconstrained,
                      "an unknown saved search lists nothing, not the whole scope")
        XCTAssertTrue(SearchPlan.make("kind:", scope: .home, home: home.path, drives: []).isUnconstrained)
        XCTAssertFalse(SearchPlan.make("conj", scope: .home, home: home.path, drives: []).isUnconstrained)
    }

    // MARK: The pane

    func testThePaneCountsAndPlacesTheInsideFilesHeader() {
        var pane = PaneState(location: .folder(URL(fileURLWithPath: downloads)), settings: ViewSettings())
        pane.navigate(to: .search(query: "conj", scope: .folder(downloads)))
        pane.setSettings(ViewSettings(sort: .relevance))
        let rows = [item("0.png", modified: now, in: downloads), item("00_Abstract.docx", modified: now - day, in: downloads),
                    item("conj notes.txt", modified: now - 9 * day, in: downloads)]
        pane.loadSearch(rows, ranks: [
            path("conj notes.txt"): SearchRank(source: .nameIndex, tier: .prefix),
            path("0.png"): SearchRank(source: .content),
            path("00_Abstract.docx"): SearchRank(source: .content),
        ])
        XCTAssertEqual(pane.items.map(\.name), ["conj notes.txt", "0.png", "00_Abstract.docx"])
        XCTAssertEqual(pane.insideFilesStart, 1)
        XCTAssertEqual(pane.searchCounts, SearchCounts(byName: 1, insideFiles: 2))
        XCTAssertEqual(ItemFormat.searchStatus(pane.searchCounts, selected: 0, total: pane.items.count, selectedBytes: nil),
                       "1 by name · 2 inside files")

        var byName = pane.settings
        byName.sort = byName.sort.clicking(.name)
        pane.setSettings(byName)
        XCTAssertEqual(pane.items.last?.name, "conj notes.txt", "by name, the digits come first")
        XCTAssertNil(pane.insideFilesStart, "the header shows only in relevance order")
        XCTAssertEqual(pane.searchCounts, SearchCounts(byName: 1, insideFiles: 2), "the status bar stays honest")

        pane.setFilter("conj")
        XCTAssertEqual(pane.searchCounts, SearchCounts(byName: 1, insideFiles: 0), "counts are of the rows shown")

        pane.hidesInsideFiles = true
        pane.replace(with: .search(query: "conj", scope: .home))
        XCTAssertTrue(pane.hidesInsideFiles, "refining or widening keeps the choice")
        pane.navigate(to: .folder(URL(fileURLWithPath: downloads)))
        XCTAssertFalse(pane.hidesInsideFiles, "a new place ends it")
        XCTAssertNil(pane.searchCounts)
        XCTAssertTrue(pane.searchRanks.isEmpty)
    }

    func testAllInsideFilesPutsTheHeaderFirst() {
        var pane = PaneState(location: .search(query: "conj", scope: .home), settings: ViewSettings(sort: .relevance))
        pane.loadSearch([item("0.png", in: downloads)], ranks: [path("0.png"): SearchRank(source: .content)])
        XCTAssertEqual(pane.insideFilesStart, 0)
        pane.loadSearch([item("conj notes.txt", in: downloads)], ranks: [path("conj notes.txt"): SearchRank(source: .nameIndex)])
        XCTAssertNil(pane.insideFilesStart, "no header without files found inside")
    }

    func testStatusWording() {
        XCTAssertEqual(ItemFormat.searchStatus(SearchCounts(byName: 12, insideFiles: 1_594), selected: 0, total: 1_606, selectedBytes: nil),
                       "12 by name · 1,594 inside files")
        XCTAssertEqual(ItemFormat.searchStatus(SearchCounts(byName: 12, insideFiles: 0, insideFilesHidden: true), selected: 0, total: 12, selectedBytes: nil),
                       "12 by name · inside files hidden")
        XCTAssertEqual(ItemFormat.searchStatus(SearchCounts(byName: 12, insideFiles: 0), selected: 0, total: 12, selectedBytes: nil), "12 items")
        XCTAssertEqual(ItemFormat.searchStatus(nil, selected: 0, total: 9, selectedBytes: nil), "9 items")
        XCTAssertEqual(ItemFormat.searchStatus(SearchCounts(byName: 1, insideFiles: 2), selected: 1, total: 3, selectedBytes: nil), "1 of 3 selected")
        XCTAssertEqual(ItemFormat.insideFilesHeader(1_594), "Found inside files (1,594)")
        XCTAssertEqual(ItemFormat.grouped(7), "7")
        XCTAssertEqual(ItemFormat.grouped(1_234_567), "1,234,567")
    }

    // MARK: The list's rows

    func testSectionedRowsMapAroundTheHeader() {
        let rows = SectionedRows(itemCount: 5, headerBefore: 2)
        XCTAssertEqual(rows.rowCount, 6)
        XCTAssertTrue(rows.isHeader(2))
        XCTAssertEqual((0..<6).map { rows.item(atRow: $0) }, [0, 1, nil, 2, 3, 4])
        XCTAssertEqual((0..<5).map { rows.row(ofItem: $0) }, [0, 1, 3, 4, 5])
        XCTAssertEqual(rows.items(inRows: 1..<4), 1..<3)
        XCTAssertNil(rows.item(atRow: 6))
        XCTAssertNil(rows.item(atRow: -1))
        let plain = SectionedRows(itemCount: 3, headerBefore: nil)
        XCTAssertEqual(plain.rowCount, 3)
        XCTAssertEqual(plain.item(atRow: 2), 2)
        XCTAssertNil(SectionedRows(itemCount: 3, headerBefore: 3).headerRow, "a header with nothing under it is not drawn")
    }

    // MARK: Saved searches

    func testSavedSearchesOpenByRelevanceUnlessASortWasChosen() {
        // Written before relevance: the window's Name A to Z was stored whether chosen or not.
        let old = SavedSearches.parse(SavedSearches.header + "\nLids\tconj\thome\t\tname:asc\tnone\nRecent\tconj\thome\t\tmodified:desc\tnone\n")
        XCTAssertNil(old.search(named: "Lids")?.sort, "opens by relevance")
        XCTAssertEqual(old.search(named: "Recent")?.sort, ItemSort(field: .modified, ascending: false))
        XCTAssertTrue(old.isLegacy, "written back in the new form")
        let rewritten = SavedSearches.parse(old.text())
        XCTAssertFalse(rewritten.isLegacy)
        XCTAssertEqual(rewritten, old)

        var chosen = SavedSearches()
        chosen.save(SavedSearch(name: "By name", query: "conj", sort: ItemSort(field: .name)))
        chosen.save(SavedSearch(name: "Best", query: "conj", sort: .relevance))
        let again = SavedSearches.parse(chosen.text())
        XCTAssertEqual(again.search(named: "By name")?.sort, ItemSort(field: .name), "a Name sort chosen since is kept")
        XCTAssertEqual(again.search(named: "Best")?.sort, .relevance)
        XCTAssertTrue(chosen.text().contains("Best\tconj\t\t\trelevance:asc\tnone\n"))
    }

    private func path(_ name: String) -> String { downloads + "/" + name }
}
