import XCTest
import IndexKit
@testable import LauncherKit

final class FilesTests: XCTestCase {
    let paths = GrandLinePaths(home: "/Users/me")

    func testPlainWordsUseTheNameIndexAndFiltersUseSpotlight() {
        let plain = FileQueryPlan.make("glau rev", content: true)
        XCTAssertEqual(plain.names, "glau rev")
        XCTAssertEqual(plain.spotlight, "glau rev")
        XCTAssertNil(FileQueryPlan.make("glau rev", content: false).spotlight)
        let filtered = FileQueryPlan.make("(glauc OR cornea) kind:pdf modified:<30d -draft", content: true)
        XCTAssertNil(filtered.names)
        XCTAssertEqual(filtered.spotlight, "(glauc OR cornea) kind:pdf modified:<30d -draft")
        XCTAssertNil(FileQueryPlan.make("\"anterior chamber\"", content: true).names)
        XCTAssertNil(FileQueryPlan.make("@weekly", content: true).names)
    }

    func testFileRowsAndActions() {
        let hit = FileHit(path: "/Users/me/Drive/01 Research/Cornea/Review v2.pdf", isFolder: false, modified: Make.noon, tier: .prefix, highlights: [0..<3])
        let row = FileResults.result(hit, paths: paths, now: Make.noon)
        XCTAssertEqual(row.title, "Review v2.pdf")
        XCTAssertEqual(row.subtitle, "…/01 Research/Cornea")
        XCTAssertEqual(row.icon, .symbol("doc.richtext"))
        XCTAssertEqual(row.accessory, "today")
        XCTAssertEqual(row.match.highlights, [0..<3])
        let titles = row.actions.map(\.title)
        XCTAssertEqual(Array(titles.prefix(3)), ["Open", "Show in Nexus", "Quick Look"])
        XCTAssertTrue(titles.contains("Open with…"))
        XCTAssertTrue(titles.contains("Copy path"))
        XCTAssertTrue(titles.contains("Copy file"))
        XCTAssertTrue(titles.contains("Move to…"))
        XCTAssertTrue(titles.contains("AirDrop"))
        XCTAssertTrue(titles.contains("Transcode: pdf"))
        XCTAssertTrue(titles.contains("Transcode: text"))
        XCTAssertEqual(row.actions.first { $0.title == "Transcode: pdf" }?.command,
                       .run("/Users/me/.grand-line/bin/transcode", arguments: ["pdf", hit.path]))
    }

    func testFoldersOpenInNexus() {
        let row = FileResults.result(FileHit(path: "/Users/me/Drive", isFolder: true), paths: paths)
        XCTAssertEqual(row.primary?.title, "Open in Nexus")
        XCTAssertEqual(row.subtitle, "~")
        XCTAssertFalse(row.actions.contains { $0.title == "Open with…" })
        XCTAssertEqual(FileResults.transcodeModes("mov"), ["video"])
        XCTAssertEqual(FileResults.transcodeModes("heic"), ["png", "jpeg"])
    }

    func testRelativeDates() {
        let day: TimeInterval = 86_400
        XCTAssertEqual(DateText.relative(Make.noon - day, now: Make.noon, calendar: Make.toronto), "yesterday")
        XCTAssertEqual(DateText.relative(Make.noon - 3 * day, now: Make.noon, calendar: Make.toronto), "3 days")
        XCTAssertEqual(DateText.relative(Make.noon - 7 * day, now: Make.noon, calendar: Make.toronto), "1 week")
        XCTAssertEqual(DateText.relative(Make.noon - 60 * day, now: Make.noon, calendar: Make.toronto), "2 months")
        XCTAssertEqual(DateText.relative(Make.noon - 800 * day, now: Make.noon, calendar: Make.toronto), "2 years")
    }

    func testFilesProviderMergesIndexAndSpotlight() async throws {
        let provider = FilesProvider(
            paths: paths,
            names: { _, _ in [IndexMatch(path: "/Users/me/a.pdf", name: "a.pdf", isFolder: false, tier: .prefix, highlights: []),
                              IndexMatch(path: "/Applications/A.app", name: "A.app", isFolder: true, tier: .prefix, highlights: [])] },
            spotlight: { _, _ in [FileHit(path: "/Users/me/a.pdf", isFolder: false), FileHit(path: "/Users/me/b.pdf", isFolder: false)] }
        )
        let global = try await provider.results(for: LaunchQuery(raw: "a"))
        XCTAssertEqual(global.map(\.title), ["a.pdf"], "global search uses names only and leaves apps to the apps provider")
        let own = try await provider.results(for: LaunchQuery(raw: ". a", prefix: .files, term: "a"))
        XCTAssertEqual(own.map(\.title), ["a.pdf", "A.app", "b.pdf"])
    }

    func testFoldersTheIndexMayNotReadAreExplained() async throws {
        let provider = FilesProvider(
            paths: paths,
            names: { _, _ in [] },
            spotlight: { _, _ in [] },
            unreadable: { ["/Users/me/Downloads", "/Users/me/Projects/app/secret", "/Users/me/Library/CloudStorage/GoogleDrive-me@example.com"] }
        )
        let rows = try await provider.results(for: LaunchQuery(raw: "conj"))
        XCTAssertEqual(rows.map(\.title), ["Allow Grand Line Index to read Downloads", "Allow Grand Line Index to read Google Drive"])
        XCTAssertEqual(rows.first?.primary?.command, .openURL(FileResults.filesAndFoldersPane, bundleID: nil))
        XCTAssertTrue(rows.allSatisfy(\.isFallback), "below every real match")
        let empty = try await provider.results(for: LaunchQuery(raw: ""))
        XCTAssertTrue(empty.isEmpty, "nothing before a search is typed")
    }

    func testPathCompletion() throws {
        let home = try Make.folder()
        for name in ["Drive/", "Downloads/", "Documents/", ".hidden/", "Dates.txt"] {
            let url = home.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Make.write("x", to: url)
            }
        }
        let provider = PathProvider(paths: GrandLinePaths(home: home.path))
        let rows = provider.instantResults(for: LaunchQuery(raw: "~/D", term: "~/D", isPath: true))
        XCTAssertEqual(rows.map(\.title), ["Dates.txt", "Documents", "Downloads", "Drive"])
        let drive = rows.first { $0.title == "Drive" }!
        XCTAssertTrue(drive.actions.contains { $0.command == .setQuery("~/Drive/") })
        XCTAssertEqual(drive.match.highlights, [0..<1])
        XCTAssertFalse(provider.instantResults(for: LaunchQuery(raw: "~/", term: "~/", isPath: true)).contains { $0.title == ".hidden" })
        XCTAssertEqual(provider.instantResults(for: LaunchQuery(raw: "~/drive", term: "~/drive", isPath: true)).first?.title, "Drive")
        XCTAssertEqual(PathProvider.split("/a/b/").folder, "/a/b/")
        XCTAssertEqual(PathProvider.split("/a/bc").partial, "bc")
    }

    func testHomeIndexSkipsLibraryButKeepsGoogleDrive() async throws {
        let home = try FolderWatcher.realPath(Make.folder().path)
        for file in [
            "Library/CloudStorage/GoogleDrive-smith@example.com/My Drive/glaucoma drive.pdf",
            "Library/Mail/glaucoma mail.eml", "Library/glaucoma prefs.plist",
            "Documents/glaucoma notes.md", "Documents/.git/glaucoma git", "Documents/app/node_modules/glaucoma.js",
            "Documents/app/.build/glaucoma.o", "Documents/Caches/glaucoma cache", ".Trash/glaucoma old.pdf",
        ] {
            try Make.write("x", to: URL(fileURLWithPath: home + "/" + file))
        }
        let rules = HomeIndexScope.exclusions(home: home)
        // A rule on ~/Library, not a list of what was there when it was read.
        XCTAssertEqual(rules.paths, [])
        XCTAssertEqual(rules.keptOnly, [home + "/Library": ["CloudStorage"]])
        XCTAssertTrue(rules.skips(path: home + "/Library/Mail"))
        XCTAssertTrue(rules.skips(path: home + "/Library/Made Next Week"))
        XCTAssertFalse(rules.skips(path: home + "/Library/CloudStorage"))
        let index = FileIndex(roots: [home], exclusions: rules)
        await index.build()
        let found = await index.search("glaucoma", limit: 50).map(\.name).sorted()
        XCTAssertEqual(found, ["glaucoma drive.pdf", "glaucoma notes.md"])
    }

    func testSavedSearches() throws {
        let file = try Make.folder().appendingPathComponent("saved-searches.tsv")
        try Make.write("# name\tquery\n@weekly\tmodified:week kind:pdf\nWeekly\tmodified:week\ncornea\tcornea kind:doc\n", to: file)
        let provider = SavedSearchProvider(file: file.path)
        provider.reload()
        XCTAssertEqual(provider.query(named: "WEEKLY"), "modified:week")
        let rows = provider.instantResults(for: LaunchQuery(raw: "@", prefix: .saved, term: ""))
        XCTAssertEqual(rows.map(\.title), ["Weekly", "cornea"])
        XCTAssertEqual(rows[1].primary?.command, .setQuery(". @cornea"))
    }
}
