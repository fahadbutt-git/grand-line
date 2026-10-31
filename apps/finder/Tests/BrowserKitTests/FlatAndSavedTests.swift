import XCTest
@testable import BrowserKit

/// Flat view, list columns, and saved searches that keep their scope,
/// columns, sort and grouping.
final class FlatAndSavedTests: XCTestCase {
    // MARK: Flat view

    func testFlatViewHasAFreeKeyAndKeepsFindersKeys() {
        XCTAssertEqual(KeyMap.command(for: .command("f", [.control, .option])), .toggleFlatView)
        XCTAssertEqual(KeyMap.command(for: .command("f", .shift)), .goRecents, "Shift+Cmd+F stays Finder's Recents")
        XCTAssertNil(KeyMap.command(for: .command("f", .control)), "Control+Cmd+F stays Enter Full Screen")
        XCTAssertTrue(MenuLayout.allCommands().contains(.toggleFlatView))
        XCTAssertEqual(KeyMap.conflicts(), [:])
    }

    func testIndexAnswersAreJoinedBelowTheFolderWithoutBackstage() {
        let folder = "/Users/me/Documents/Projects"
        let batches = [
            [folder + "/Conj Flap/notes.txt", folder + "/Conj Flap", "/Users/me/Documents/other.txt"],
            [folder + "/Conj Flap/notes.txt", folder + "/site/node_modules/pkg/index.js", folder + "/.git/config"],
            [folder + "/Lid Repair/.hidden.txt", folder + "/App.app/Contents/Info.plist", folder, folder + "/Lid Repair"],
        ]
        XCTAssertEqual(FlatListing.merge(batches, under: folder, home: home.path, showHidden: false), [
            folder + "/Conj Flap",
            folder + "/Conj Flap/notes.txt",
            folder + "/Lid Repair",
        ])
        let withHidden = FlatListing.merge(batches, under: folder, home: home.path, showHidden: true)
        XCTAssertTrue(withHidden.contains(folder + "/Lid Repair/.hidden.txt"))
        XCTAssertFalse(withHidden.contains(folder + "/.git/config"), ".git is skipped even with hidden files shown")
        XCTAssertEqual(FlatListing.merge(batches, under: folder, home: home.path, showHidden: false, limit: 2).count, 2)
        XCTAssertTrue(FlatListing.isPartial([["a", "b"], ["c"]], probeLimit: 2))
        XCTAssertFalse(FlatListing.isPartial([["a"], ["c"]], probeLimit: 2))
    }

    func testEveryNameHasAProbe() {
        for name in ["report.pdf", "2024", "x", "R", "-", "_", "Ünïcödé"] {
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            XCTAssertTrue(FlatListing.probes.contains { folded.contains($0) }, name)
        }
    }

    func testFoldersTheIndexSkipsAreReadFromDisk() {
        XCTAssertTrue(FlatListing.needsDisk("/Users/me/.Trash", home: home.path))
        XCTAssertTrue(FlatListing.needsDisk("/Users/me/Library/Caches", home: home.path))
        XCTAssertTrue(FlatListing.needsDisk("/Applications", home: home.path))
        XCTAssertFalse(FlatListing.needsDisk("/Users/me/Documents", home: home.path))
    }

    func testTheDiskWalkSkipsBackstage() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.file("Project/a.txt")
        try temp.file("Project/Drafts/v1/b.txt")
        try temp.file("Project/node_modules/pkg/c.js")
        try temp.file("Project/.git/HEAD")
        try temp.file("Project/.notes.txt")
        let folder = temp.url("Project")
        let found = FlatListing.walk(folder, home: temp.root.path, showHidden: false).map { String($0.dropFirst(folder.path.count + 1)) }
        XCTAssertEqual(found, ["a.txt", "Drafts", "Drafts/v1", "Drafts/v1/b.txt"])
        let hidden = FlatListing.walk(folder, home: temp.root.path, showHidden: true).map { String($0.dropFirst(folder.path.count + 1)) }
        XCTAssertTrue(hidden.contains(".notes.txt"))
        XCTAssertFalse(hidden.contains { $0.hasPrefix(".git") })
        XCTAssertEqual(FlatListing.walk(folder, home: temp.root.path, showHidden: false, limit: 2).count, 2)
    }

    func testThePathColumnIsTheFolderBelowTheFlatOne() {
        let folder = "/Users/me/Documents/Projects"
        XCTAssertEqual(FlatListing.relativeFolder(of: folder + "/Conj Flap/Drafts/v2/x.docx", under: folder), "Conj Flap/Drafts/v2")
        XCTAssertEqual(FlatListing.relativeFolder(of: folder + "/top.txt", under: folder + "/"), "")
        XCTAssertEqual(FlatListing.relativeFolder(of: "/Volumes/x/y.txt", under: "/"), "Volumes/x")
    }

    func testFlatIsATransientScopeNotAViewSetting() {
        var pane = PaneState(location: .folder(documents))
        pane.isFlat = true
        let stored = ViewPreferences().settings(for: documents.path, window: pane.settings)
        XCTAssertEqual(stored, ViewSettings(), "flat view never reaches the stored settings")
        XCTAssertEqual(ListColumn.shown(nil, flat: true), [.name, .path, .modified, .size, .kind])
        XCTAssertEqual(ListColumn.shown([.size, .name, .size], flat: false), [.name, .size])
    }

    // MARK: Columns

    func testColumnsRoundTripAndOldSettingsStillLoad() throws {
        XCTAssertEqual(ListColumn.parse("name, Modified,bogus,size"), [.name, .modified, .size])
        XCTAssertNil(ListColumn.parse("bogus"))
        XCTAssertEqual(ListColumn.text([.name, .added]), "name,added")
        let old = #"{"mode":"list","sort":{"field":"name","ascending":true},"iconSize":64}"#
        let decoded = try JSONDecoder().decode(ViewSettings.self, from: Data(old.utf8))
        XCTAssertNil(decoded.columns)
        let chosen = ViewSettings(columns: [.name, .path, .size])
        let again = try JSONDecoder().decode(ViewSettings.self, from: JSONEncoder().encode(chosen))
        XCTAssertEqual(again.columns, [.name, .path, .size])
    }

    // MARK: Saved searches

    func testSavedSearchesKeepScopeColumnsSortAndGrouping() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        var saved = SavedSearches()
        saved.save(SavedSearch(
            name: "Recent papers", query: "kind:pdf modified:<30d", scope: .folder("/Users/me/Documents"),
            columns: [.name, .path, .modified], sort: ItemSort(field: .modified, ascending: false, foldersFirst: true, grouping: .kind)
        ))
        saved.save(SavedSearch(name: "Everything conj", query: "conj", scope: .mac))
        let file = temp.url("saved-searches.tsv")
        try saved.write(to: file)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix(SavedSearches.header + "\n"))
        XCTAssertTrue(text.contains("Recent papers\tkind:pdf modified:<30d\tfolder:/Users/me/Documents\tname,path,modified\tmodified:desc+folders\tkind\n"))
        let loaded = SavedSearches.load(file)
        XCTAssertEqual(loaded, saved)
        XCTAssertFalse(loaded.isLegacy)
        let papers = try XCTUnwrap(loaded.search(named: "recent PAPERS"))
        XCTAssertEqual(papers.scope, .folder("/Users/me/Documents"))
        XCTAssertEqual(papers.columns, [.name, .path, .modified])
        XCTAssertEqual(papers.sort?.grouping, .kind)
        XCTAssertEqual(papers.sort?.foldersFirst, true)
        XCTAssertEqual(loaded.search(named: "Everything conj")?.runScope, .mac)
    }

    /// Files from before: name and query only. They load with the home folder
    /// (where they always ran), are marked for writing back, and Sight's two
    /// fields stay first.
    func testOldEntriesMigrate() throws {
        let old = SavedSearches.parse("# name\tquery\n@weekly\tmodified:<7d\npapers\tkind:pdf glaucoma\n")
        XCTAssertTrue(old.isLegacy)
        XCTAssertEqual(old.names, ["weekly", "papers"])
        XCTAssertEqual(old.search(named: "weekly")?.scope, .home)
        XCTAssertNil(old.search(named: "weekly")?.columns)
        XCTAssertNil(old.search(named: "papers")?.sort)
        let rewritten = SavedSearches.parse(old.text())
        XCTAssertFalse(rewritten.isLegacy)
        XCTAssertEqual(rewritten, old)
        let line = old.text().split(separator: "\n")[1].split(separator: "\t", omittingEmptySubsequences: false)
        XCTAssertEqual(line.prefix(2).map(String.init), ["weekly", "modified:<7d"], "Sight reads the first two fields")
        XCTAssertFalse(SavedSearches.parse("").isLegacy, "an empty file needs nothing")
    }

    func testSortAndGroupFields() {
        XCTAssertEqual(SavedSearches.parseSort("size:asc", group: ""), ItemSort(field: .size, ascending: true))
        XCTAssertEqual(SavedSearches.parseSort("lastOpened", group: "none"), ItemSort(field: .lastOpened))
        XCTAssertEqual(SavedSearches.parseSort("", group: "kind"), ItemSort(grouping: .kind))
        XCTAssertNil(SavedSearches.parseSort("", group: ""))
        XCTAssertNil(SavedSearches.parseSort("nonsense", group: "none"))
        XCTAssertEqual(SavedSearches.parseScope("folder:/Users/me/Desktop"), .folder("/Users/me/Desktop"))
        XCTAssertNil(SavedSearches.parseScope("folder:relative"))
        XCTAssertEqual(SavedSearches.scopeText(.drive), "drive")
    }
}
