import XCTest
@testable import BrowserKit

/// History, Up (R4) and opening.
final class NavigationTests: XCTestCase {
    func testBackAndForward() {
        var history = NavigationHistory(.folder(home))
        history.visit(.folder(documents))
        history.visit(.recents)
        XCTAssertEqual(history.back(), .folder(documents))
        XCTAssertEqual(history.back(), .folder(home))
        XCTAssertNil(history.back())
        XCTAssertEqual(history.forward(), .folder(documents))
        XCTAssertTrue(history.canGoForward)
        history.visit(.folder(URL(fileURLWithPath: "/Applications")))
        XCTAssertFalse(history.canGoForward, "a new place clears Forward")
    }

    func testVisitingTheSamePlaceAddsNothing() {
        var history = NavigationHistory(.folder(home))
        history.visit(.folder(home))
        XCTAssertFalse(history.canGoBack)
    }

    func testHistoryIsCapped() {
        var history = NavigationHistory(.folder(home))
        for i in 0..<250 { history.visit(.folder(URL(fileURLWithPath: "/tmp/\(i)"))) }
        XCTAssertEqual(history.backStack.count, NavigationHistory.limit)
    }

    func testParentOfFolderSelectsWhereYouCameFrom() {
        let parent = BrowserLocation.folder(documents).parent
        XCTAssertEqual(parent?.location, .folder(home))
        XCTAssertEqual(parent?.select?.path, documents.path)
        XCTAssertNil(BrowserLocation.folder(URL(fileURLWithPath: "/")).parent)
        XCTAssertNil(BrowserLocation.recents.parent)
    }

    func testParentInsideArchive() {
        let zip = documents.appendingPathComponent("Data.zip")
        XCTAssertEqual(BrowserLocation.archive(zip, entry: "a/b").parent?.location, .archive(zip, entry: "a"))
        XCTAssertEqual(BrowserLocation.archive(zip, entry: "a").parent?.location, .archive(zip, entry: ""))
        XCTAssertEqual(BrowserLocation.archive(zip, entry: "").parent?.location, .folder(documents))
        XCTAssertEqual(BrowserLocation.archive(zip, entry: "").parent?.select, zip)
    }

    func testUpSelectsTheFolderYouLeft() {
        var pane = PaneState(location: .folder(documents))
        XCTAssertTrue(pane.goUp())
        XCTAssertEqual(pane.location, .folder(home))
        pane.load([item("Documents", folder: true, in: "/Users/me"), item("Desktop", folder: true, in: "/Users/me")])
        pane.applyPendingSelection()
        XCTAssertEqual(pane.selectedItems.map(\.name), ["Documents"])
    }

    func testOpeningOneFolderNavigates() {
        let pane = PaneState(location: .folder(home))
        let action = pane.openAction(for: [item("Documents", folder: true, in: "/Users/me")])
        XCTAssertEqual(action.navigate, .folder(documents))
        XCTAssertTrue(action.launch.isEmpty)
    }

    func testOpeningFilesLaunchesThem() {
        let pane = PaneState(location: .folder(documents))
        let action = pane.openAction(for: [item("a.pdf"), item("b.docx")])
        XCTAssertEqual(action.launch.map(\.lastPathComponent), ["a.pdf", "b.docx"])
        XCTAssertNil(action.navigate)
    }

    func testOpeningSeveralFoldersOpensWindows() {
        let pane = PaneState(location: .folder(documents))
        let action = pane.openAction(for: [item("A", folder: true), item("B", folder: true)])
        XCTAssertEqual(action.windows.count, 2)
    }

    func testOpeningAnArchiveBrowsesIt() {
        let pane = PaneState(location: .folder(documents))
        let action = pane.openAction(for: [item("Supplement.zip")])
        XCTAssertEqual(action.navigate, .archive(documents.appendingPathComponent("Supplement.zip"), entry: ""))
    }

    func testOpeningInsideAnArchive() {
        let zip = documents.appendingPathComponent("Data.zip")
        let pane = PaneState(location: .archive(zip, entry: ""))
        let folder = FileItem(url: zip.appendingPathComponent("Figures"), name: "Figures", isFolder: true, archiveEntry: "Figures")
        XCTAssertEqual(pane.openAction(for: [folder]).navigate, .archive(zip, entry: "Figures"))
        let file = FileItem(url: zip.appendingPathComponent("a.png"), name: "a.png", isFolder: false, archiveEntry: "a.png")
        XCTAssertEqual(pane.openAction(for: [file]).fromArchive, [file])
    }

    func testSearchRefinesInPlace() {
        var pane = PaneState(location: .folder(documents))
        pane.navigate(to: .search(query: "gl", scope: .home))
        pane.replace(with: .search(query: "glaucoma", scope: .home))
        XCTAssertEqual(pane.history.backStack, [.folder(documents)])
    }

    func testTitles() {
        XCTAssertEqual(BrowserLocation.folder(documents).title, "Documents")
        XCTAssertEqual(BrowserLocation.recents.title, "Recents")
        XCTAssertEqual(BrowserLocation.folder(URL(fileURLWithPath: "/private/tmp/journey/.Trash")).title, "Trash")
        XCTAssertEqual(BrowserLocation.archive(documents.appendingPathComponent("D.zip"), entry: "x/y").title, "y")
        XCTAssertNil(BrowserLocation.archive(documents, entry: "").folderURL, "nothing is written inside an archive")
    }
}
