import FileKit
import IndexKit
import XCTest
@testable import BrowserKit

/// R2, R3 and R18: scopes that widen, QueryKit plans, saved searches, merging.
final class SearchTests: XCTestCase {
    func testScopesStartInTheFolderAndWiden() {
        let chips = SearchScope.chips(from: documents.path)
        XCTAssertEqual(chips, [.folder(documents.path), .home, .drive, .mac])
        XCTAssertEqual(chips.first?.title, "Documents")
        XCTAssertEqual(SearchScope.folder(documents.path).wider, .home)
        XCTAssertEqual(SearchScope.home.wider, .drive)
        XCTAssertEqual(SearchScope.drive.wider, .mac)
        XCTAssertNil(SearchScope.mac.wider)
        XCTAssertEqual(SearchScope.chips(from: nil).first, .home)
    }

    func testSpotlightRoots() {
        XCTAssertEqual(SearchScope.folder(documents.path).spotlightScopes(home: home.path, drives: []), [documents.path])
        XCTAssertEqual(SearchScope.home.spotlightScopes(home: home.path, drives: []), [home.path])
        XCTAssertEqual(SearchScope.mac.spotlightScopes(home: home.path, drives: []), [NSMetadataQueryLocalComputerScope])
        XCTAssertEqual(SearchScope.drive.spotlightScopes(home: home.path, drives: []), [home.path], "no drive falls back to home")
    }

    func testNameResultsAreKeptInScope() {
        XCTAssertTrue(SearchScope.folder("/Users/me/Documents").contains("/Users/me/Documents/a.pdf", home: home.path, drives: []))
        XCTAssertFalse(SearchScope.folder("/Users/me/Documents").contains("/Users/me/DocumentsOld/a.pdf", home: home.path, drives: []))
        XCTAssertFalse(SearchScope.home.contains("/Applications/Preview.app", home: home.path, drives: []))
        XCTAssertTrue(SearchScope.mac.contains("/Applications/Preview.app", home: home.path, drives: []))
    }

    func testPlanUsesQueryKit() {
        let plan = SearchPlan.make("glaucoma kind:pdf", scope: .folder(documents.path), home: home.path, drives: [])
        XCTAssertFalse(plan.hasIssues)
        XCTAssertEqual(plan.scopes, [documents.path])
        XCTAssertNil(plan.nameText, "kinds need Spotlight")
        XCTAssertTrue(plan.chips.contains("PDF") || plan.chips.contains { $0.contains("PDF") })
        XCTAssertFalse(plan.predicate.predicateFormat.contains("LIKE"))
    }

    func testPlainWordsGoToTheNameIndexToo() {
        let plan = SearchPlan.make("cornea notes", scope: .home, home: home.path, drives: [])
        XCTAssertEqual(plan.nameText, "cornea notes")
        XCTAssertTrue(plan.accepts("/Users/me/Documents/cornea notes.md"))
        XCTAssertFalse(plan.accepts("/Applications/cornea.app"))
    }

    func testQueryFoldersOverrideTheScope() {
        let plan = SearchPlan.make("report in:~/Downloads", scope: .folder(documents.path), home: home.path, drives: [])
        XCTAssertEqual(plan.scopes, ["/Users/me/Downloads"])
        XCTAssertTrue(plan.accepts("/Users/me/Downloads/report.pdf"))
    }

    func testSavedSearchesExpand() {
        let saved = SavedSearches.parse("# name\tquery\n@weekly\tmodified:<7d\npapers\tkind:pdf glaucoma\n")
        XCTAssertEqual(saved.names, ["weekly", "papers"])
        XCTAssertEqual(saved.query(named: "WEEKLY"), "modified:<7d")
        let plan = SearchPlan.make("@papers", scope: .home, home: home.path, drives: [], savedSearch: { saved.query(named: $0) })
        XCTAssertFalse(plan.hasIssues)
    }

    func testSavedSearchesRoundTrip() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        var saved = SavedSearches()
        saved.save("Papers", query: "kind:pdf")
        saved.save("papers", query: "kind:pdf cornea")
        saved.save("Weekly", query: "modified:week")
        XCTAssertEqual(saved.names, ["papers", "Weekly"], "names ignore case and the newest wins")
        let file = temp.url("saved-searches.tsv")
        try saved.write(to: file)
        XCTAssertEqual(SavedSearches.load(file), saved)
        saved.remove("weekly")
        XCTAssertEqual(saved.names, ["papers"])
    }

    func testMergeKeepsNameMatchesFirst() {
        let merged = SearchResults.merge(names: ["/a", "/b"], spotlight: ["/c", "/a", "/d"], limit: 3)
        XCTAssertEqual(merged, ["/a", "/b", "/c"])
    }

    func testNameMatchesAreFilteredByThePlan() {
        let plan = SearchPlan.make("notes", scope: .folder(documents.path), home: home.path, drives: [])
        let matches = [
            IndexMatch(path: "/Users/me/Documents/notes.md", name: "notes.md", isFolder: false, tier: .prefix, highlights: []),
            IndexMatch(path: "/Users/me/Desktop/notes.md", name: "notes.md", isFolder: false, tier: .prefix, highlights: []),
        ]
        XCTAssertEqual(SearchResults.names(matches, plan: plan), ["/Users/me/Documents/notes.md"])
    }

    func testNameMatchesLeadAndAppDataContentMatchesAreDropped() {
        let plan = SearchPlan.make("conj", scope: .mac, home: home.path, drives: [])
        let spotlight = [
            "/Users/me/Library/Application Support/Code/Cache/733.js",
            "/Users/me/Documents/notes.md",
            "/Users/me/Downloads/Conj Flap",
            "/Users/me/.vscode/extensions/server.mjs",
            "/Users/me/Projects/site/node_modules/pkg/index.js",
            "/Applications/Tool.app/Contents/Resources/app.js",
            "/System/Library/Frameworks/x.js",
            "/Users/me/Library/CloudStorage/GoogleDrive-me@example.com/My Drive/eye exam.docx",
            "/Users/me/Downloads/Lid Study - CONJ",
        ]
        let merged = SearchResults.merge(names: [], spotlight: spotlight, plan: plan)
        XCTAssertEqual(merged, [
            "/Users/me/Downloads/Conj Flap",
            "/Users/me/Downloads/Lid Study - CONJ",
            "/Users/me/Documents/notes.md",
            "/Users/me/Library/CloudStorage/GoogleDrive-me@example.com/My Drive/eye exam.docx",
        ])
    }

    func testContentMatchesStayWhenTheSearchIsInsideAppData() {
        let cache = "/Users/me/Library/Application Support/Code"
        let plan = SearchPlan.make("conj", scope: .folder(cache), home: home.path, drives: [])
        XCTAssertTrue(plan.keepsContentMatch(cache + "/Cache/733.js"))
        XCTAssertFalse(plan.keepsContentMatch(cache + "/node_modules/a.js"), "still skips what IndexKit skips below the scope")
        let hidden = SearchPlan.make("conj in:~/.config", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(hidden.keepsContentMatch("/Users/me/.config/app/settings.json"))
        XCTAssertFalse(SearchPlan.make("conj", scope: .home, home: home.path, drives: []).keepsContentMatch("/Users/me/.config/app/settings.json"))
    }

    func testAppDataNameMatchesAreDroppedFromBothSources() {
        // The journeys' fixture: a package folder named like the query, inside
        // node_modules in the folder searched.
        let projects = "/Users/me/Documents/Projects/Conj Flap"
        let module = projects + "/node_modules/conj-module"
        let plan = SearchPlan.make("conj", scope: .folder(documents.path), home: home.path, drives: [])
        let matches = [
            IndexMatch(path: projects + "/conj notes.txt", name: "conj notes.txt", isFolder: false, tier: .prefix, highlights: []),
            IndexMatch(path: module, name: "conj-module", isFolder: true, tier: .prefix, highlights: []),
            IndexMatch(path: "/Users/me/Documents/.cache/conj-junk.tmp", name: "conj-junk.tmp", isFolder: false, tier: .prefix, highlights: []),
        ]
        XCTAssertEqual(SearchResults.names(matches, plan: plan), [projects + "/conj notes.txt"])
        let merged = SearchResults.merge(names: [], spotlight: [module, module + "/index.js", projects + "/conj notes.txt"], plan: plan)
        XCTAssertEqual(merged, [projects + "/conj notes.txt"])
    }

    func testAHomeOutsideUsersIsStillAPersonsFolder() {
        // A fixture home in a temporary folder under /private: only the part
        // of a path below the home counts, so its files are not system files.
        let fixture = "/private/var/folders/x/T/journeyhome"
        let plan = SearchPlan.make("conj", scope: .mac, home: fixture, drives: [])
        XCTAssertTrue(plan.keeps(fixture + "/Documents/conj notes.txt"))
        XCTAssertFalse(plan.keeps(fixture + "/Library/Caches/com.example.app/conj-cache.db"))
        XCTAssertFalse(plan.keeps("/private/var/db/conj.plist"))
    }

    func testFoldersTheIndexSkipsAreReadFromDisk() {
        XCTAssertEqual(SearchPlan.make("conj", scope: .folder("/Users/me/.Trash"), home: home.path, drives: []).foldersTheIndexSkips,
                       ["/Users/me/.Trash"])
        XCTAssertEqual(SearchPlan.make("conj", scope: .folder("/Users/me/Library/Mail"), home: home.path, drives: []).foldersTheIndexSkips,
                       ["/Users/me/Library/Mail"])
        XCTAssertEqual(SearchPlan.make("conj", scope: .folder(documents.path), home: home.path, drives: []).foldersTheIndexSkips, [])
        XCTAssertEqual(SearchPlan.make("conj", scope: .folder("/Users/me/Library/CloudStorage/GoogleDrive-a@b.c"), home: home.path, drives: []).foldersTheIndexSkips, [])
        XCTAssertEqual(SearchPlan.make("conj", scope: .home, home: home.path, drives: []).foldersTheIndexSkips, [])
    }

    func testTheTrashIsSearchedByName() throws {
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("SearchTests-\(UUID().uuidString)/.Trash")
        try FileManager.default.createDirectory(at: trash.appendingPathComponent("Old Folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: trash.deletingLastPathComponent()) }
        for name in ["old conj draft.docx", "trashed CONJ note.txt", "scratch.txt", "Old Folder/conj inside.txt", ".conj hidden"] {
            try Data("x".utf8).write(to: trash.appendingPathComponent(name))
        }
        let found = FolderNameScan.paths(in: [trash.path], words: ["conj"]).map { ($0 as NSString).lastPathComponent }.sorted()
        XCTAssertEqual(found, ["conj inside.txt", "old conj draft.docx", "trashed CONJ note.txt"])
        XCTAssertEqual(FolderNameScan.paths(in: [trash.path], words: ["conj"], limit: 1).count, 1)
        XCTAssertEqual(FolderNameScan.paths(in: [trash.path], words: []), [])
    }

    func testAnEmptySearchSaysWhereItLookedAndOffersTheMac() {
        let trash = PaneEmptyState.make(for: .search(query: "conj", scope: .folder("/Users/me/.Trash")), folderTitle: "Trash")
        XCTAssertEqual(trash.message, "No results in Trash.")
        XCTAssertEqual(trash.widenTitle, "Search This Mac?")
        XCTAssertEqual(trash.widen, .mac)
        XCTAssertEqual(PaneEmptyState.make(for: .search(query: "conj", scope: .folder(documents.path))).message, "No results in Documents.")
        XCTAssertEqual(PaneEmptyState.make(for: .search(query: "conj", scope: .home)).message, "No results in Home.")
        XCTAssertEqual(PaneEmptyState.make(for: .search(query: "conj", scope: .mac)), PaneEmptyState(message: "No matches", widen: nil))
        XCTAssertEqual(PaneEmptyState.make(for: .folder(documents)).message, "Empty folder")
        XCTAssertEqual(PaneEmptyState.make(for: .recents).message, "No recent files")
    }

    func testNameMatchesIgnoreCaseAndAccents() {
        let plan = SearchPlan.make("cafe menu", scope: .home, home: home.path, drives: [])
        XCTAssertTrue(plan.matchesName("/Users/me/Café Menu.pdf"))
        XCTAssertFalse(plan.matchesName("/Users/me/Café.pdf"))
    }
}
