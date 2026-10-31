import XCTest
@testable import BrowserKit

/// A pane holding a 100,000-item folder: loading, sorting, selecting, moving
/// the selection and pruning stay quick. Limits are loose in debug builds:
/// `swift test -c release -Xswiftc -enable-testing --filter BrowserKitTests.StressTests`.
final class StressTests: XCTestCase {
    static func folder(_ count: Int) -> [FileItem] {
        let words = ["glaucoma", "cornea", "retina", "draft", "figure", "table", "notes", "budget", "photo", "summary"]
        let exts = ["pdf", "docx", "png", "csv", "md"]
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        return (0..<count).map { i in
            let isFolder = i % 50 == 0
            let name = "\(words[next() % words.count]) \(i)" + (isFolder ? "" : "." + exts[next() % exts.count])
            return FileItem(
                url: URL(fileURLWithPath: "/Stress/" + name), name: name, isFolder: isFolder,
                size: isFolder ? nil : Int64(next() % 1_000_000), modified: Date(timeIntervalSince1970: Double(next() % 1_000_000_000)),
                kind: isFolder ? "Folder" : "Document"
            )
        }
    }

    #if DEBUG
    let limit = 30.0
    #else
    let limit = 3.0
    #endif

    func testHundredThousandItems() {
        let items = Self.folder(100_000)
        let start = Date()
        var pane = PaneState(location: .folder(URL(fileURLWithPath: "/Stress")))
        pane.load(items)
        XCTAssertEqual(pane.items.count, 100_000)
        XCTAssertTrue(pane.items.prefix(2_000).allSatisfy(\.isFolder), "folders first")

        pane.setSettings(ViewSettings(sort: ItemSort(field: .size)))
        XCTAssertGreaterThanOrEqual(pane.items[2_000].size ?? 0, pane.items[2_001].size ?? 0)
        pane.setSettings(ViewSettings(sort: ItemSort(field: .modified, foldersFirst: false)))

        pane.selection.selectAll(pane.ids)
        XCTAssertEqual(pane.selectedItems.count, 100_000)
        pane.selection.select(pane.ids[50_000])
        for _ in 0..<100 { pane.selection.move(by: 1, in: pane.ids, extending: true) }
        XCTAssertEqual(pane.selection.count, 101)

        pane.load(Array(items.dropLast(10_000)))
        XCTAssertEqual(pane.items.count, 90_000)

        let order = pane.moveManually([pane.items[89_999].name], to: 0)
        XCTAssertEqual(order.count, 90_000)
        XCTAssertEqual(pane.items.first?.name, order.first)

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, limit, "100,000-item pane took \(elapsed) s")
    }

    func testTypeSelectAndColumnWidthOnALargeFolder() {
        let names = Self.folder(100_000).map(\.name)
        let start = Date()
        var typing = TypeSelect()
        XCTAssertNotNil(typing.type("retina 9", names: names))
        let width = ColumnWidth.fitting(names) { Double($0.count) * 7 }
        XCTAssertGreaterThanOrEqual(width, ColumnWidth.minimum)
        XCTAssertLessThan(Date().timeIntervalSince(start), limit)
    }
}
