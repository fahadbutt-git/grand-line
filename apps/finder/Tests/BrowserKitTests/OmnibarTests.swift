import XCTest
@testable import BrowserKit

/// The path bar's field as one keyboard target: paths with completion, a
/// filter on the folder, `?` search and `>` commands, and Finder's keys kept.
final class OmnibarTests: XCTestCase {
    let drive = URL(fileURLWithPath: "/Users/me/Library/CloudStorage/GoogleDrive-smith@example.com/My Drive", isDirectory: true)

    func testWhatTheTextAsksFor() {
        XCTAssertEqual(Omnibar.mode(for: "~/Documents", origin: .filter), .path("~/Documents"))
        XCTAssertEqual(Omnibar.mode(for: "/Applications", origin: .filter), .path("/Applications"))
        XCTAssertEqual(Omnibar.mode(for: "Papers/2024", origin: .filter), .path("Papers/2024"))
        XCTAssertEqual(Omnibar.mode(for: "Drive", origin: .filter, aliases: ["Drive": drive]), .path("Drive"))
        XCTAssertEqual(Omnibar.mode(for: "conj", origin: .filter), .filter("conj"))
        XCTAssertEqual(Omnibar.mode(for: "?conj kind:pdf", origin: .filter), .search("conj kind:pdf"))
        XCTAssertEqual(Omnibar.mode(for: "> new tab", origin: .filter), .command("new tab"))
        XCTAssertEqual(Omnibar.mode(for: "", origin: .filter), .filter(""))
    }

    /// Shift+Cmd+G keeps Finder's Go to Folder: a name is a folder to go to, never a filter.
    func testGoToFolderKeepsFindersMeaning() {
        XCTAssertEqual(Omnibar.mode(for: "Lid Repair", origin: .goToFolder), .folderName("Lid Repair"))
        XCTAssertEqual(Omnibar.mode(for: "~/Documents/Projects", origin: .goToFolder), .path("~/Documents/Projects"))
        XCTAssertEqual(Omnibar.mode(for: "?notes", origin: .goToFolder), .search("notes"))
        XCTAssertEqual(KeyMap.command(for: .command("g", .shift)), .goToFolder)
        XCTAssertEqual(KeyMap.command(for: .command("f")), .find)
        XCTAssertEqual(KeyMap.command(for: .command("g", .option)), .filterFolder)
    }

    func testFilterAndSearchLookDifferent() {
        let filter = Omnibar.Mode.filter("a")
        let search = Omnibar.Mode.search("a")
        XCTAssertNotEqual(filter.badge, search.badge)
        XCTAssertNotEqual(filter.symbol, search.symbol)
        XCTAssertEqual(filter.badge, "Filter")
        XCTAssertEqual(search.badge, "Search")
        XCTAssertEqual(Omnibar.Mode.command("x").badge, "Command")
    }

    func testCommandsMatchByTitleAndSubmenu() {
        XCTAssertEqual(Omnibar.commands(matching: "new tab").first?.command, .newTab)
        XCTAssertEqual(Omnibar.commands(matching: "new tab").first?.shortcut, "⌘T")
        XCTAssertEqual(Omnibar.commands(matching: "date added").first?.command, .sortAdded)
        XCTAssertEqual(Omnibar.commands(matching: "date added").first?.title, "Sort By › Date Added")
        XCTAssertTrue(Omnibar.commands(matching: "trash").map(\.command).contains(.moveToTrash))
        XCTAssertEqual(Omnibar.commands(matching: "zzzz"), [])
        XCTAssertEqual(Omnibar.commands(matching: "", limit: 3).map(\.command), [.newWindow, .newTab, .newFolder])
        let available = Omnibar.commands(matching: "trash") { $0 != .moveToTrash }
        XCTAssertFalse(available.map(\.command).contains(.moveToTrash), "commands that do not apply are left out")
    }

    func testTabCompletesOneFolderOrWhatSeveralShare() {
        let editable: (URL) -> String = { PathSegments.editableText(for: $0, home: home) }
        let one = [URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)]
        XCTAssertEqual(PathInput.complete("~/Doc", options: one, editable: editable), "~/Documents/")
        let several = [
            URL(fileURLWithPath: "/Users/me/Documents/Project Alpha", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Documents/project beta", isDirectory: true),
        ]
        XCTAssertEqual(PathInput.complete("~/Documents/pro", options: several, editable: editable), "~/Documents/Project ")
        XCTAssertNil(PathInput.complete("~/Nothing", options: [], editable: editable))
        XCTAssertEqual(PathInput.commonPrefix(["Alpha", "alphabet", "ALPS"]), "Alp")
    }

    func testCompletionListsMatchingChildFolders() {
        let found = PathInput.completions(for: "~/Documents/pa", relativeTo: documents, home: home) { _ in
            ["Papers", "Patients", "Drafts", "paperwork"]
        }
        XCTAssertEqual(found.map(\.lastPathComponent), ["Papers", "paperwork", "Patients"])
    }

    func testPathsAreTold() {
        XCTAssertTrue(PathInput.looksLikePath("~"))
        XCTAssertTrue(PathInput.looksLikePath("./x"))
        XCTAssertTrue(PathInput.looksLikePath("a/b"))
        XCTAssertFalse(PathInput.looksLikePath("notes"))
        XCTAssertFalse(PathInput.looksLikePath("   "))
    }

    // MARK: Filter

    func testFilterMatchesWordsIgnoringCaseAndAccents() {
        XCTAssertTrue(ItemFilter.matches("Conj Flap protocol.pdf", "conj"))
        XCTAssertTrue(ItemFilter.matches("Conj Flap protocol.pdf", "flap PROTO"))
        XCTAssertFalse(ItemFilter.matches("Conj Flap protocol.pdf", "flap draft"))
        XCTAssertTrue(ItemFilter.matches("Résumé.docx", "resume"))
        XCTAssertTrue(ItemFilter.matches("anything", "  "))
        XCTAssertTrue(ItemFilter.matches("report 2024.pdf", "*.pdf"))
        XCTAssertFalse(ItemFilter.matches("report.pdf.zip", "*.pdf"))
        XCTAssertTrue(ItemFilter.matches("v1.docx", "v?.docx"))
    }

    func testFilterNarrowsRowsAndTheSelectionAndClearsOnLeaving() {
        var pane = PaneState(location: .folder(documents))
        pane.load([item("conj notes.txt"), item("report.pdf"), item("Conj figure.png")])
        pane.selection.set(pane.ids, in: pane.ids)
        pane.setFilter("conj")
        XCTAssertEqual(pane.items.map(\.name), ["Conj figure.png", "conj notes.txt"])
        XCTAssertEqual(pane.unfilteredCount, 3)
        XCTAssertEqual(pane.selectedItems.count, 2, "hidden rows leave the selection")
        pane.load([item("conj notes.txt"), item("report.pdf"), item("Conj figure.png"), item("conj new.txt")])
        XCTAssertEqual(pane.items.count, 3, "new rows are filtered too")
        pane.setFilter("")
        XCTAssertEqual(pane.items.count, 4)
        pane.setFilter("report")
        pane.navigate(to: .folder(home))
        XCTAssertEqual(pane.filter, "", "a filter belongs to its folder")
    }

    func testEscapeClearsAFilterWhereverTheKeysAre() {
        // After Return the keys are back with the list (or the window): Escape clears.
        XCTAssertTrue(FilterEscape.clears(filter: "notes", typing: false, modifiers: [], sheetOpen: false))
        // Nothing filtered, a field being typed in, a modifier or a sheet: not this Escape.
        XCTAssertFalse(FilterEscape.clears(filter: "", typing: false, modifiers: [], sheetOpen: false))
        XCTAssertFalse(FilterEscape.clears(filter: "notes", typing: true, modifiers: [], sheetOpen: false))
        XCTAssertFalse(FilterEscape.clears(filter: "notes", typing: false, modifiers: [.command], sheetOpen: false))
        XCTAssertFalse(FilterEscape.clears(filter: "notes", typing: false, modifiers: [], sheetOpen: true))
    }
}
