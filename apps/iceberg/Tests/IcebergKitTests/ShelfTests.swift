import XCTest
@testable import IcebergKit

/// The shelf: its list, its file, bookmarks, and the quick actions' names
/// and commands. Nothing here may change, move or delete a shelved file.
final class ShelfTests: XCTestCase {
    func item(_ path: String, id: String? = nil) -> ShelfItem {
        ShelfItem(id: id ?? UUID().uuidString, name: (path as NSString).lastPathComponent, path: path,
                  bookmark: Data(path.utf8), added: Date(timeIntervalSince1970: 1_000))
    }

    // MARK: The list

    func testAddPutsNewestFirstWithoutDuplicates() {
        var list = ShelfList()
        let a = item("/tmp/a.txt"), b = item("/tmp/b.txt")
        XCTAssertEqual(list.add([a, b]), [a.id, b.id])
        XCTAssertEqual(list.items.map(\.path), ["/tmp/a.txt", "/tmp/b.txt"])
        let c = item("/tmp/c.txt")
        let again = item("/tmp/./a.txt")
        XCTAssertEqual(list.add([c, again]), [c.id], "a file already there is not added twice")
        XCTAssertEqual(list.items.map(\.name), ["c.txt", "a.txt", "b.txt"])
        XCTAssertEqual(list.items[1].id, a.id, "the existing item keeps its id")
        XCTAssertTrue(list.contains(path: "/tmp/b.txt"))
    }

    func testTheSameFileTwiceInOneDropShowsOnce() {
        var list = ShelfList()
        list.add([item("/tmp/x"), item("/tmp/x")])
        XCTAssertEqual(list.items.count, 1)
    }

    func testRemoveOnlyTakesTheBookmark() throws {
        let folder = TempFolder()
        let file = folder.write("keep.txt", "still here")
        var list = ShelfList()
        let i = item(file.path)
        list.add([i])
        list.remove(id: i.id)
        XCTAssertTrue(list.items.isEmpty)
        list.add([item(file.path)])
        list.removeAll()
        XCTAssertTrue(list.items.isEmpty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "still here")
    }

    func testOldestFallOffPastTheLimit() {
        var list = ShelfList()
        for n in 0..<(ShelfList.maxItems + 5) { list.add([item("/tmp/f\(n)")]) }
        XCTAssertEqual(list.items.count, ShelfList.maxItems)
        XCTAssertEqual(list.items.first?.path, "/tmp/f\(ShelfList.maxItems + 4)")
        XCTAssertFalse(list.contains(path: "/tmp/f0"))
    }

    func testUpdateFollowsAMovedFile() {
        var list = ShelfList()
        let i = item("/tmp/old.txt")
        list.add([i])
        list.update(id: i.id, path: "/tmp/new.txt", name: "new.txt", bookmark: Data([1, 2]))
        XCTAssertEqual(list.items.first?.path, "/tmp/new.txt")
        XCTAssertEqual(list.items.first?.bookmark, Data([1, 2]))
        list.update(id: "missing", path: "/x", name: "x", bookmark: nil)
        XCTAssertEqual(list.items.count, 1)
    }

    // MARK: The file

    func testFileRoundTrip() throws {
        let folder = TempFolder()
        let url = folder.url.appendingPathComponent("state/shelf.json")
        var list = ShelfList()
        list.add([item("/tmp/a.png", id: "A"), item("/tmp/b.pdf", id: "B")])
        try ShelfFile.save(list, to: url)
        XCTAssertEqual(ShelfFile.load(from: url), list)
    }

    func testBrokenOrMissingFileIsAnEmptyShelf() {
        let folder = TempFolder()
        XCTAssertEqual(ShelfFile.load(from: folder.url.appendingPathComponent("none.json")), ShelfList())
        let bad = folder.write("bad.json", "{ not json")
        XCTAssertEqual(ShelfFile.load(from: bad), ShelfList())
        let future = folder.write("future.json", #"{"version": 99, "items": []}"#)
        XCTAssertNil(ShelfFile.decode(try! Data(contentsOf: future)))
    }

    #if canImport(Darwin)
    func testBookmarksFollowARename() throws {
        let folder = TempFolder()
        let file = folder.write("report.txt", "x")
        let made = try XCTUnwrap(ShelfBookmark.item(for: file))
        XCTAssertEqual(made.name, "report.txt")
        XCTAssertEqual(ShelfBookmark.resolve(made)?.url.standardizedFileURL.resolvingSymlinksInPath().path,
                       file.standardizedFileURL.resolvingSymlinksInPath().path)
        let moved = folder.url.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        let found = try XCTUnwrap(ShelfBookmark.resolve(made))
        XCTAssertEqual(found.url.lastPathComponent, "renamed.txt")
    }

    func testAGoneFileDoesNotResolve() throws {
        let gone = ShelfItem(name: "gone", path: "/nonexistent-\(UUID().uuidString)", bookmark: Data([0, 1, 2]))
        XCTAssertNil(ShelfBookmark.resolve(gone))
    }
    #endif

    // MARK: Names for new files

    func testOutputNamesNeverClash() {
        let src = URL(fileURLWithPath: "/w/photo.png")
        var taken: Set<String> = ["/w/photo.png"]
        let exists: (URL) -> Bool = { taken.contains($0.path) }
        XCTAssertEqual(OutputName.unique(for: src, suffix: "compressed", ext: "jpg", exists: exists)?.path, "/w/photo-compressed.jpg")
        taken.insert("/w/photo-compressed.jpg")
        XCTAssertEqual(OutputName.unique(for: src, suffix: "compressed", ext: "jpg", exists: exists)?.path, "/w/photo-compressed 2.jpg")
        // Converting to the same extension never names the original.
        XCTAssertEqual(OutputName.unique(for: src, suffix: nil, ext: "png", exists: exists)?.path, "/w/photo 2.png")
        let folder = URL(fileURLWithPath: "/w/Album.v2")
        XCTAssertEqual(OutputName.unique(for: folder, suffix: nil, ext: "zip", isDirectory: true, exists: exists)?.path, "/w/Album.v2.zip")
        XCTAssertNil(OutputName.unique(for: src, suffix: "x", ext: "y", exists: { _ in true }))
    }

    func testActionsOfferedByKind() {
        let png = URL(fileURLWithPath: "/w/a.PNG")
        XCTAssertEqual(QuickAction.available(for: png, isDirectory: false),
                       [.zip, .compress, .convert(.jpeg), .convert(.heic), .convert(.tiff), .removeBackground])
        XCTAssertEqual(QuickAction.available(for: URL(fileURLWithPath: "/w/notes.txt"), isDirectory: false), [.zip])
        XCTAssertEqual(QuickAction.available(for: URL(fileURLWithPath: "/w/pics.png"), isDirectory: true), [.zip])
        XCTAssertTrue(QuickAction.available(for: URL(fileURLWithPath: "/w/a.gif"), isDirectory: false).contains(.convert(.png)))
    }

    func testCommandsWriteOnlyANewFile() throws {
        let none: (URL) -> Bool = { _ in false }
        let jpg = URL(fileURLWithPath: "/w/My Photo.jpeg")
        let zip = try XCTUnwrap(QuickActionPlan.invocation(.zip, source: jpg, isDirectory: false, exists: none))
        XCTAssertEqual(zip.executable, "/usr/bin/ditto")
        XCTAssertEqual(zip.arguments, ["-c", "-k", "--sequesterRsrc", "--keepParent", "/w/My Photo.jpeg", "/w/My Photo.zip"])

        let small = try XCTUnwrap(QuickActionPlan.invocation(.compress, source: jpg, isDirectory: false, exists: none))
        XCTAssertEqual(small.output.path, "/w/My Photo-compressed.jpeg")
        XCTAssertEqual(small.arguments, ["-s", "format", "jpeg", "-s", "formatOptions", "70", "/w/My Photo.jpeg", "--out", "/w/My Photo-compressed.jpeg"])

        let png = URL(fileURLWithPath: "/w/shot.png")
        let pngSmall = try XCTUnwrap(QuickActionPlan.invocation(.compress, source: png, isDirectory: false, exists: none))
        XCTAssertEqual(pngSmall.output.lastPathComponent, "shot-compressed.jpg")

        let heic = try XCTUnwrap(QuickActionPlan.invocation(.convert(.heic), source: png, isDirectory: false, exists: none))
        XCTAssertEqual(heic.executable, "/usr/bin/sips")
        XCTAssertEqual(heic.arguments, ["-s", "format", "heic", "/w/shot.png", "--out", "/w/shot.heic"])

        XCTAssertNil(QuickActionPlan.invocation(.removeBackground, source: png, isDirectory: false, exists: none))
        XCTAssertEqual(QuickAction.removeBackground.destination(for: png, isDirectory: false, exists: none)?.lastPathComponent,
                       "shot-cutout.png")
        for action in QuickAction.available(for: png, isDirectory: false) {
            let out = action.destination(for: png, isDirectory: false, exists: { $0.path == png.path })
            XCTAssertNotEqual(out?.path, png.path, "\(action) would write over the original")
        }
    }

    #if os(macOS)
    func testZipMakesANewFileAndLeavesTheOriginal() throws {
        let folder = TempFolder()
        let file = folder.write("data.txt", "hello")
        folder.write("data.zip", "taken")
        let plan = try XCTUnwrap(QuickActionPlan.invocation(.zip, source: file, isDirectory: false,
                                                            exists: { FileManager.default.fileExists(atPath: $0.path) }))
        XCTAssertEqual(plan.output.lastPathComponent, "data 2.zip")
        let done = expectation(description: "zip")
        let result = Collector<Bool>()
        ToolRunner.run(plan) { r in
            if case .success = r { result.set("ok", true) }
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        XCTAssertEqual(result.values["ok"], true)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
        XCTAssertEqual(try String(contentsOf: folder.url.appendingPathComponent("data.zip"), encoding: .utf8), "taken")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.output.path))
    }

    func testRunnerRefusesANameTakenMeanwhile() {
        let folder = TempFolder()
        let taken = folder.write("out.zip", "mine")
        let plan = ToolInvocation(executable: "/usr/bin/true", arguments: [], output: taken)
        let done = expectation(description: "refused")
        ToolRunner.run(plan) { r in
            XCTAssertEqual(r, .failure(.outputExists))
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try String(contentsOf: taken, encoding: .utf8), "mine")
    }
    #endif

    // MARK: Settings

    func testShelfAndDragSettings() {
        let d = IcebergSettings()
        XCTAssertTrue(d.shelfQuickActions)
        XCTAssertFalse(d.dragBasket)
        XCTAssertEqual(d.noNotchStyle, .island)
        let (s, issues) = IcebergSettings.parse("""
        shelf_quick_actions = false
        drag_basket = true
        no_notch_style = "Notch"
        """)
        XCTAssertEqual(issues, [])
        XCTAssertFalse(s.shelfQuickActions)
        XCTAssertTrue(s.dragBasket)
        XCTAssertEqual(s.noNotchStyle, .notch)
        let (bad, problems) = IcebergSettings.parse("no_notch_style = \"round\"")
        XCTAssertEqual(bad.noNotchStyle, .island)
        XCTAssertEqual(problems.count, 1)
    }

    func testABadSaveKeepsThePreviousValue() throws {
        let folder = TempFolder()
        let url = folder.write("iceberg.toml", "drag_basket = true\nhud_volume = true\n")
        let first = IcebergSettings.reload(from: url, previous: nil).settings
        XCTAssertTrue(first.dragBasket)
        folder.write("iceberg.toml", "drag_basket = \"yes\"\nhud_volume = true\n")
        let next = IcebergSettings.reload(from: url, previous: first)
        XCTAssertTrue(next.settings.dragBasket, "a value turned down keeps the one in use")
        XCTAssertTrue(next.settings.hudVolume)
    }

    // MARK: Geometry for displays without a notch, and dropping

    let builtin = ScreenInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                             auxiliaryLeftWidth: 663, auxiliaryRightWidth: 664, menuBarHeight: 32, isBuiltin: true)
    let external = ScreenInfo(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), menuBarHeight: 25)

    func testClosedRadii() {
        let notch = NotchGeometry.closedRadii(style: .notch, look: .island, height: 32)
        XCTAssertEqual(notch.top, NotchMetrics.collapsedTopRadius)
        XCTAssertEqual(notch.bottom, NotchMetrics.collapsedBottomRadius)
        let island = NotchGeometry.closedRadii(style: .pill, look: .island, height: 25)
        XCTAssertEqual(island.top, 0)
        XCTAssertEqual(island.bottom, 12.5)
        let tab = NotchGeometry.closedRadii(style: .pill, look: .notch, height: 25)
        XCTAssertEqual(tab.bottom, NotchMetrics.collapsedBottomRadius)
    }

    func testDropZoneSurroundsTheNotchBelowTheTopEdge() {
        let hit = NotchGeometry.hitZone(of: builtin, style: .notch)
        let drop = NotchGeometry.dropZone(of: builtin, style: .notch)
        XCTAssertTrue(drop.contains(hit))
        XCTAssertEqual(drop.maxY, builtin.frame.maxY)
        XCTAssertEqual(drop.minY, hit.minY - NotchGeometry.dropMargin.height)
        XCTAssertEqual(drop.width, hit.width + 2 * NotchGeometry.dropMargin.width)
        let pill = NotchGeometry.dropZone(of: external, style: .pill)
        XCTAssertEqual(pill.midX, external.frame.midX, accuracy: 1)
    }

    func testHUDWingsAreWiderThanTheMusicWings() {
        let hud = NotchGeometry.hudPanelSize(of: builtin)
        let live = NotchGeometry.collapsedPanelSize(of: builtin, liveActivity: true)
        XCTAssertGreaterThan(hud.width, live.width)
        XCTAssertEqual(hud.height, 32)
        XCTAssertEqual(hud.width, 185 + 2 * NotchGeometry.hudWingWidth(collapsedHeight: 32) + 2 * NotchMetrics.collapsedTopRadius)
        XCTAssertLessThan(hud.width, builtin.frame.width / 2)
    }
}
