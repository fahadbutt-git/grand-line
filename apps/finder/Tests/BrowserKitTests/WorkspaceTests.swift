import XCTest
@testable import BrowserKit

/// R12 and R27: workspaces saved and loaded.
final class WorkspaceTests: XCTestCase {
    func sample(_ name: String) -> Workspace {
        let zip = home.appendingPathComponent("Downloads/Supplementary data.zip")
        return Workspace(
            name: name, layout: PaneLayout(count: 3, focused: 1),
            panes: [
                .init(location: .folder(home.appendingPathComponent("Downloads")), mode: .list),
                .init(location: .folder(documents), mode: .list),
                .init(location: .archive(zip, entry: ""), mode: .list),
            ],
            pinned: true, sidebarWidth: 240
        )
    }

    func testSaveLoadListAndRemove() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let store = WorkspaceStore(folder: temp.url("Workspaces"))
        try store.save(sample("Glaucoma submission"))
        try store.save(sample("Cornea / review"))
        XCTAssertEqual(store.names(), ["Cornea / review", "Glaucoma submission"])
        XCTAssertEqual(store.load("Glaucoma submission"), sample("Glaucoma submission"))
        XCTAssertNil(store.load("Missing"))
    }

    func testSearchesComeBackAsHome() {
        var workspace = sample("x")
        workspace.panes[1] = .init(location: .search(query: "glaucoma", scope: .home), mode: .icons)
        let restored = workspace.restorable(home: home)
        XCTAssertEqual(restored.panes[1].location, .folder(home))
        XCTAssertEqual(restored.panes[1].mode, .icons)
    }

    func testMissingPanesAreFilledIn() {
        let workspace = Workspace(name: "x", layout: PaneLayout(count: 2), panes: [.init(location: .folder(documents), mode: .list)])
        XCTAssertEqual(workspace.restorable(home: home).panes.count, 2)
    }
}
