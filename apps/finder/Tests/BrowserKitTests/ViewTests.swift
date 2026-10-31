import XCTest
@testable import BrowserKit

/// R6, R7 and R28: views, per-folder exceptions, sorting, manual order, column widths.
final class ViewTests: XCTestCase {
    func testFiveViewsNumberedForCommandKeys() {
        XCTAssertEqual(ViewMode.allCases.map(\.number), [1, 2, 3, 4, 5])
        XCTAssertEqual(ViewMode.numbered(1), .icons)
        XCTAssertEqual(ViewMode.numbered(5), .panes)
        XCTAssertNil(ViewMode.numbered(6))
        XCTAssertEqual(KeyMap.command(for: .command("3")), .viewColumns)
        XCTAssertEqual(KeyMap.command(for: .command("5")), .viewPanes)
    }

    func testOneSettingEverywhereWithExceptions() {
        var prefs = ViewPreferences()
        let window = ViewSettings(mode: .icons)
        XCTAssertEqual(prefs.settings(for: "/Users/me/Downloads", window: window).mode, .icons)
        prefs.remember(ViewSettings(mode: .list, sort: ItemSort(field: .modified)), for: "/Users/me/Downloads/")
        XCTAssertEqual(prefs.settings(for: "/Users/me/Downloads", window: window).mode, .list, "trailing slashes do not matter")
        XCTAssertEqual(prefs.settings(for: "/Users/me/Documents", window: window).mode, .icons)
        XCTAssertFalse(prefs.change(ViewSettings(mode: .gallery), in: "/Users/me/Documents"), "a plain folder follows the window")
        XCTAssertTrue(prefs.change(ViewSettings(mode: .gallery), in: "/Users/me/Downloads"))
        XCTAssertEqual(prefs.settings(for: "/Users/me/Downloads", window: window).mode, .gallery)
        prefs.forget("/Users/me/Downloads")
        XCTAssertFalse(prefs.hasException("/Users/me/Downloads"))
    }

    func testPreferencesAreStoredByTheAppNotInDSStore() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let folder = try temp.folder("Project")
        let paths = AppPaths(home: temp.root, support: temp.root.appendingPathComponent("Support"))
        var prefs = ViewPreferences()
        prefs.remember(ViewSettings(mode: .columns), for: folder.path)
        prefs.setManualOrder(["b", "a"], for: folder.path)
        try JSONFile<ViewPreferences>(paths.viewPreferences).write(prefs)
        XCTAssertEqual(JSONFile<ViewPreferences>(paths.viewPreferences).read(), prefs)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".DS_Store").path))
    }

    func testSortingKeepsFoldersFirstAndUsesNaturalOrder() {
        let items = [item("file 10.txt"), item("Zeta", folder: true), item("file 2.txt"), item("alpha", folder: true)]
        let sorted = ItemSorter.sorted(items, by: ItemSort(field: .name, foldersFirst: true))
        XCTAssertEqual(sorted.map(\.name), ["alpha", "Zeta", "file 2.txt", "file 10.txt"])
        let mixed = ItemSorter.sorted(items, by: ItemSort(field: .name))
        XCTAssertEqual(mixed.map(\.name), ["alpha", "file 2.txt", "file 10.txt", "Zeta"], "one sort key by default")
    }

    func testDateSortMixesFoldersAndFilesUnlessAskedToStack() {
        func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
        let items = [
            item("old folder", folder: true, modified: at(1_000), kind: "Folder"),
            item("new.pdf", modified: at(9_000), kind: "PDF document"),
            item("mid folder", folder: true, modified: at(5_000), kind: "Folder"),
            item("mid.docx", modified: at(4_000), kind: "Word document"),
            item("old.pdf", modified: at(2_000), kind: "PDF document"),
        ]
        let byDate = ItemSort(field: .modified)
        XCTAssertEqual(ItemSorter.sorted(items, by: byDate).map(\.name), ["new.pdf", "mid folder", "mid.docx", "old.pdf", "old folder"])
        var stacked = byDate
        stacked.grouping = .kind
        XCTAssertEqual(ItemSorter.sorted(items, by: stacked).map(\.name), ["mid folder", "old folder", "new.pdf", "old.pdf", "mid.docx"])
        stacked.foldersFirst = true
        stacked.grouping = .none
        XCTAssertEqual(ItemSorter.sorted(items, by: stacked).map(\.name), ["mid folder", "old folder", "new.pdf", "mid.docx", "old.pdf"])
        XCTAssertTrue(stacked.clicking(.name).foldersFirst, "changing the column keeps the stacked choices")
    }

    func testSortChoicesAreSavedAndOldSettingsLoadAsOneKey() throws {
        var sort = ItemSort(field: .added, foldersFirst: true, grouping: .kind)
        let data = try JSONEncoder().encode(sort)
        XCTAssertEqual(try JSONDecoder().decode(ItemSort.self, from: data), sort)
        let old = Data(#"{"field":"added","ascending":false,"foldersFirst":true}"#.utf8)
        sort = try JSONDecoder().decode(ItemSort.self, from: old)
        XCTAssertEqual(sort, ItemSort(field: .added))
        XCTAssertFalse(sort.foldersFirst)
    }

    func testSortBySizeUsesFolderSizes() {
        let items = [item("small.txt", size: 10), item("Big", folder: true), item("mid.txt", size: 500)]
        let sorted = ItemSorter.sorted(items, by: ItemSort(field: .size, foldersFirst: false),
                                       folderSizes: [items[1].path: 9_000])
        XCTAssertEqual(sorted.map(\.name), ["Big", "mid.txt", "small.txt"], "largest first by default")
    }

    func testSortByDateNewestFirstAndClickingFlips() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 9_000)
        let items = [item("old", modified: old), item("new", modified: new)]
        let sort = ItemSort(field: .modified)
        XCTAssertEqual(ItemSorter.sorted(items, by: sort).map(\.name), ["new", "old"])
        XCTAssertEqual(ItemSorter.sorted(items, by: sort.clicking(.modified)).map(\.name), ["old", "new"])
        XCTAssertEqual(sort.clicking(.name).field, .name)
        XCTAssertTrue(sort.clicking(.name).ascending)
    }

    func testChoosingASortGivesItsDefaultDirectionAndClickingFlips() {
        let byName = ItemSort(field: .name, foldersFirst: true, grouping: .kind)
        XCTAssertTrue(byName.ascending)
        // A header click on the active column flips it, as in Finder.
        let flipped = byName.clicking(.name)
        XCTAssertFalse(flipped.ascending)
        XCTAssertTrue(flipped.clicking(.name).ascending)
        // View › Sort By › Name (or its shortcut) sorts A to Z however it was sorted.
        XCTAssertTrue(flipped.choosing(.name).ascending)
        XCTAssertTrue(byName.choosing(.name).ascending)
        XCTAssertEqual(byName.choosing(.name), byName)
        XCTAssertEqual(flipped.choosing(.modified).field, .modified)
        XCTAssertEqual(flipped.choosing(.modified).ascending, SortField.modified.defaultAscending)
        XCTAssertTrue(flipped.choosing(.size).foldersFirst)
        XCTAssertEqual(flipped.choosing(.size).grouping, .kind)
    }

    func testSortByLastOpenedAddedAndTags() {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 9_000)
        let a = FileItem(url: URL(fileURLWithPath: "/t/a"), name: "a", isFolder: false, added: early, tags: ["Red"])
        let b = FileItem(url: URL(fileURLWithPath: "/t/b"), name: "b", isFolder: false, added: late, tags: ["Blue"])
        let c = FileItem(url: URL(fileURLWithPath: "/t/c"), name: "c", isFolder: false)
        let items = [a, b, c]
        let opened = ItemSorter.sorted(items, by: ItemSort(field: .lastOpened), lastOpened: ["/t/a": late, "/t/c": early])
        XCTAssertEqual(opened.map(\.name), ["a", "c", "b"], "most recently opened first, never opened last")
        XCTAssertEqual(ItemSorter.sorted(items, by: ItemSort(field: .added)).map(\.name), ["b", "a", "c"])
        XCTAssertEqual(ItemSorter.sorted(items, by: ItemSort(field: .tags)).map(\.name), ["b", "a", "c"], "untagged last")

        var pane = PaneState(location: .folder(URL(fileURLWithPath: "/t")), settings: ViewSettings(sort: ItemSort(field: .lastOpened)))
        pane.load(items)
        pane.setLastOpened(["/t/b": late])
        XCTAssertEqual(pane.items.first?.name, "b", "dates arriving later resort the pane")
    }

    func testManualOrder() {
        let items = [item("a"), item("b"), item("c"), item("new")]
        XCTAssertEqual(ManualOrder.apply(["c", "a", "b"], to: items).map(\.name), ["c", "a", "b", "new"])
        XCTAssertEqual(ManualOrder.move(["c"], to: 0, in: ["a", "b", "c"]), ["c", "a", "b"])
        XCTAssertEqual(ManualOrder.move(["a"], to: 3, in: ["a", "b", "c"]), ["b", "c", "a"])
        XCTAssertEqual(ManualOrder.move(["a", "c"], to: 2, in: ["a", "b", "c", "d"]), ["b", "a", "c", "d"])
    }

    func testDraggingRowsSwitchesToManualOrder() {
        var pane = PaneState(location: .folder(documents))
        pane.load([item("a"), item("b"), item("c")])
        let order = pane.moveManually(["c"], to: 0)
        XCTAssertEqual(order, ["c", "a", "b"])
        XCTAssertEqual(pane.settings.sort.field, .manual)
        XCTAssertEqual(pane.items.map(\.name), ["c", "a", "b"])
    }

    func testNameColumnFitsTheLongestName() {
        let measure: (String) -> Double = { Double($0.count) * 7 }
        XCTAssertEqual(ColumnWidth.fitting(["a"], measure: measure), ColumnWidth.minimum)
        let long = String(repeating: "x", count: 40)
        XCTAssertEqual(ColumnWidth.fitting(["a", long], measure: measure), 280 + ColumnWidth.chrome)
        XCTAssertEqual(ColumnWidth.fitting([String(repeating: "x", count: 500)], measure: measure), ColumnWidth.maximum)
    }

    func testIconSizesAreBounded() {
        XCTAssertTrue(ViewSettings.iconSizes.contains(ViewSettings().iconSize))
    }
}
