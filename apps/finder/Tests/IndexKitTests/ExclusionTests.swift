import XCTest
@testable import IndexKit

final class ExclusionTests: XCTestCase {
    private var folder = ""

    override func setUpWithError() throws {
        folder = try Fixture.folder()
        for path in [
            "a/.DS_Store", "a/._keep.txt", "a/.git/config", "a/node_modules/left.js", "a/.build/out.o",
            "a/Caches/cached.db", "a/Viewer.app/Contents/Info.plist", "a/keep.txt", "a/sub/keep two.txt",
        ] {
            try Fixture.make(path, in: folder)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: folder)
    }

    func testStandardExclusions() async {
        let index = FileIndex(roots: [folder])
        await index.build()
        let keep = await index.search("keep")
        XCTAssertEqual(Set(names(keep)), ["keep.txt", "keep two.txt"])
        for hidden in ["ds_store", "config", "left", "out.o", "cached", "info.plist", "contents"] {
            let found = await index.search(hidden)
            XCTAssertTrue(found.isEmpty, hidden)
        }
        let app = await index.search("viewer")
        XCTAssertEqual(app.first?.name, "Viewer.app")
        XCTAssertEqual(app.first?.isFolder, false)
        // The root, a, sub, Viewer.app and the two kept files.
        let count = await index.count
        XCTAssertEqual(count, 6)
    }

    func testCustomExclusions() async {
        let only = IndexExclusions(names: ["sub"], paths: [folder + "/a/.git"])
        let index = FileIndex(roots: [folder], exclusions: only)
        await index.build()
        let two = await index.search("keep two")
        XCTAssertTrue(two.isEmpty)
        let left = await index.search("left")
        XCTAssertEqual(left.first?.name, "left.js")
        let config = await index.search("config")
        XCTAssertTrue(config.isEmpty)
        let plist = await index.search("info.plist")
        XCTAssertEqual(plist.first?.name, "Info.plist")
    }

    func testRules() {
        let rules = IndexExclusions.standard
        XCTAssertTrue(rules.skips(".DS_Store"))
        XCTAssertTrue(rules.skips("._Report.docx"))
        XCTAssertTrue(rules.skips("node_modules"))
        XCTAssertFalse(rules.skips("Report.docx"))
        XCTAssertTrue(rules.isPackage("Safari.app"))
        XCTAssertTrue(rules.isPackage("Photos Library.photoslibrary"))
        XCTAssertTrue(rules.isPackage("Thing.APP"))
        XCTAssertFalse(rules.isPackage("app"))
        XCTAssertFalse(rules.isPackage("Folder"))
        XCTAssertFalse(IndexExclusions.none.skips(".DS_Store"))
        XCTAssertTrue(IndexExclusions(paths: ["/x/y"]).skips(path: "/x/y"))
        XCTAssertFalse(IndexExclusions(paths: ["/x/y"]).skips(path: "/x/y/z"))
    }

    func testOverlappingRootsAreMerged() {
        let index = FileIndex(roots: [folder, folder + "/a", folder + "/"])
        XCTAssertEqual(index.roots, [folder])
    }
}
