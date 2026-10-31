import FileKit
import XCTest
@testable import BrowserKit

/// The models behind Nexus's Settings window: the defaults round trip, the
/// sidebar's order and Tags section, the Return key choice, where new windows
/// and searches start, and names without extensions.
final class SettingsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "BrowserKitSettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNothingStoredKeepsTodaysBehaviour() {
        let prefs = NexusPreferences(defaults: defaults)
        XCTAssertEqual(prefs, NexusPreferences())
        XCTAssertEqual(prefs.returnKey, .open, "Return opens, as before Settings")
        XCTAssertEqual(prefs.newWindowTarget, .currentFolder)
        XCTAssertTrue(prefs.openFoldersInTabs)
        XCTAssertTrue(prefs.showPathBar && prefs.showStatusBar && prefs.showAllExtensions && prefs.includeContentMatches)
        XCTAssertFalse(prefs.showHiddenFiles)
        XCTAssertFalse(prefs.sidebar.showsTags, "no Tags section until one is chosen")
    }

    func testRoundTrip() {
        var prefs = NexusPreferences()
        prefs.newWindowTarget = .downloads
        prefs.openFoldersInTabs = false
        prefs.returnKey = .rename
        prefs.showStatusBar = false
        prefs.showKindColours = false
        prefs.includeContentMatches = false
        prefs.defaultSearchScope = .home
        prefs.showHiddenFiles = true
        prefs.showAllExtensions = false
        prefs.warnBeforeEmptyingTrash = false
        prefs.sidebar.move(.locations, by: -10)
        prefs.sidebar.setTag("Red", shown: true)
        prefs.sidebar.setTag("In review", shown: true)
        prefs.sidebar.setTag("Gray", favourite: false)
        prefs.save(to: defaults)
        XCTAssertEqual(NexusPreferences(defaults: defaults), prefs)
        XCTAssertEqual(defaults.string(forKey: NexusPreferences.Key.returnKey), "rename")
    }

    func testReturnRenamesOnlyWhenChosen() {
        let returnKey = Shortcut(.returnKey)
        XCTAssertEqual(ReturnKeyAction.open.command(.open, for: returnKey), .open)
        XCTAssertEqual(ReturnKeyAction.rename.command(.open, for: returnKey), .rename)
        XCTAssertEqual(ReturnKeyAction.rename.command(.open, for: Shortcut(.character("o"), .command)), .open, "Cmd+O still opens")
        XCTAssertEqual(ReturnKeyAction.rename.command(.openSelection, for: Shortcut(.down, .command)), .openSelection)
    }

    func testNewWindowAndSearchStartingPoints() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.folder("Library/CloudStorage/GoogleDrive-journey")
        let drive = try XCTUnwrap(GoogleDrive.accounts(home: temp.root).first)
        XCTAssertEqual(NewWindowTarget.currentFolder.location(current: documents, home: home, drives: []), .folder(documents))
        XCTAssertEqual(NewWindowTarget.currentFolder.location(current: nil, home: home, drives: []), .folder(home))
        XCTAssertEqual(NewWindowTarget.downloads.location(current: documents, home: home, drives: []),
                       .folder(home.appendingPathComponent("Downloads", isDirectory: true)))
        XCTAssertEqual(NewWindowTarget.drive.location(current: nil, home: home, drives: [drive]), .folder(drive.myDrive))
        XCTAssertEqual(NewWindowTarget.recents.location(current: nil, home: home, drives: []), .recents)

        XCTAssertEqual(DefaultSearchScope.currentFolder.scope(folder: documents), .folder(documents.path))
        XCTAssertEqual(DefaultSearchScope.currentFolder.scope(folder: nil), .home)
        XCTAssertEqual(DefaultSearchScope.mac.scope(folder: documents), .mac)
    }

    func testSidebarOrderAndHiddenItems() {
        var layout = SidebarLayout()
        layout.move(.locations, by: -3)
        layout.setTag("Blue", shown: true)
        let input = SidebarBuilder.Input(
            home: home, places: [documents], savedSearches: ["papers"], trash: home.appendingPathComponent(".Trash"),
            layout: layout
        )
        XCTAssertEqual(SidebarBuilder.build(input).map(\.section), [.locations, .places, .savedSearches, .tags])

        let places = SidebarBuilder.build(input).first { $0.section == .places }!.items.map(\.id)
        layout.move(item: "folder:" + documents.path, in: .places, by: -5, shown: places)
        var moved = input
        moved.layout = layout
        let reordered = SidebarBuilder.build(moved).first { $0.section == .places }!.items.map(\.title)
        XCTAssertEqual(reordered, ["Documents", "Recents", "AirDrop"])

        let tags = SidebarBuilder.build(moved).first { $0.section == .tags }!.items
        XCTAssertEqual(tags.map(\.title), ["Blue"])
        XCTAssertEqual(tags.first?.target, .location(.search(query: "tag:Blue", scope: .home)))
        XCTAssertEqual(SidebarLayout.query(for: "In review"), "tag:\"In review\"")

        var hidden = SidebarHidden()
        hidden.hide(.tags)
        moved.hidden = hidden
        XCTAssertFalse(SidebarBuilder.build(moved).contains { $0.section == .tags })
        XCTAssertTrue(SidebarBuilder.everything(moved).contains { $0.section == .tags }, "Settings still lists it")
        hidden.show(.tags)
        moved.hidden = hidden
        XCTAssertTrue(SidebarBuilder.build(moved).contains { $0.section == .tags })
    }

    func testTagsAreUniqueIgnoringCase() {
        var layout = SidebarLayout()
        layout.setTag("Urgent", shown: true)
        layout.setTag("urgent", shown: true)
        XCTAssertEqual(layout.tags, ["Urgent"])
        layout.setTag("URGENT", shown: false)
        XCTAssertEqual(layout.tags, [])
        XCTAssertEqual(SidebarLayout().favouriteTags, TagEditor.colors)
    }

    func testNamesWithoutExtensions() {
        let report = item("Report.final.pdf")
        XCTAssertEqual(report.shownName(allExtensions: true), "Report.final.pdf")
        XCTAssertEqual(report.shownName(allExtensions: false), "Report.final")
        XCTAssertEqual(item("Projects.v2", folder: true).shownName(allExtensions: false), "Projects.v2")
        XCTAssertEqual(item("Makefile").shownName(allExtensions: false), "Makefile")
        XCTAssertEqual(report.typedName("Summary", allExtensions: false), "Summary.pdf", "the hidden extension comes back")
        XCTAssertEqual(report.typedName("Summary.docx", allExtensions: false), "Summary.docx")
        XCTAssertEqual(report.typedName("Summary", allExtensions: true), "Summary")
    }
}
