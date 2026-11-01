import ArchiveKit
import FileKit
import XCTest
@testable import BrowserKit

/// Compress names chosen when the task runs (N1), items from several folders
/// (N12), Put Back for Finder's items and for a name reused in the Trash (N8),
/// Apply to All (N21), Tab with one pane (N20) and which folders get sizes (N7).
final class SafetyFlowTests: XCTestCase {
    private var temp: TempFolder!

    override func setUpWithError() throws {
        temp = try TempFolder()
    }

    override func tearDown() {
        temp.remove()
    }

    private var hasTools: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/bsdtar") && FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto")
    }

    private func names(_ relative: String = "") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: temp.url(relative).path)) ?? []).sorted()
    }

    private func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: Compress

    func testTwoCompressTasksNeverShareANameNorOverwrite() async throws {
        try XCTSkipUnless(hasTools)
        try temp.file("Archive.zip", "the person's own")
        let a = try temp.file("a.txt"), b = try temp.file("b.txt"), c = try temp.file("c.txt"), d = try temp.file("d.txt")
        let ops = FileOperations(trash: { $0 })
        let firstPlan = try XCTUnwrap(CompressPlan.make(for: [a, b]))
        let secondPlan = try XCTUnwrap(CompressPlan.make(for: [c, d]))
        async let first = Compressor.run(firstPlan, operations: ops)
        async let second = Compressor.run(secondPlan, operations: ops)
        let made = try await [first, second]
        XCTAssertEqual(Set(made.map(\.lastPathComponent)), ["Archive 2.zip", "Archive 3.zip"])
        XCTAssertEqual(text(temp.url("Archive.zip")), "the person's own")
        XCTAssertFalse(names().contains { $0.hasPrefix(".compressing-") })
        let one = try XCTUnwrap(CompressPlan.make(for: [a]))
        let single = try await Compressor.run(one, operations: ops)
        XCTAssertEqual(single.lastPathComponent, "a.txt.zip")
    }

    func testCompressTakesEachItemFromItsOwnFolder() async throws {
        try XCTSkipUnless(hasTools)
        let report = try temp.file("A/report.txt", "report")
        try temp.file("A/data.csv", "the wrong one")
        let data = try temp.file("B/data.csv", "1,2")
        let plan = try XCTUnwrap(CompressPlan.make(for: [report, data]))
        let made = try await Compressor.run(plan, operations: FileOperations(trash: { $0 }))
        XCTAssertEqual(made.deletingLastPathComponent().lastPathComponent, "A")
        let out = try temp.folder("out")
        try Archive.extract(["report.txt", "data.csv"], from: made, to: out)
        XCTAssertEqual(text(out.appendingPathComponent("data.csv")), "1,2")
        XCTAssertEqual(text(out.appendingPathComponent("report.txt")), "report")
    }

    func testAFailedCompressLeavesNothingUnderTheName() async throws {
        try XCTSkipUnless(hasTools)
        let trash = try temp.folder("Trash")
        let ops = FileOperations(trash: { url in
            let destination = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        try temp.folder("work")
        let plan = try XCTUnwrap(CompressPlan.make(for: [temp.url("work/missing one"), temp.url("work/missing two")]))
        do {
            try await Compressor.run(plan, operations: ops)
            XCTFail("compressing missing items succeeded")
        } catch {}
        XCTAssertEqual(names("work"), [], "no Archive.zip and no working file left; a half archive is in the Trash")
    }

    func testCompressPlanArguments() throws {
        let a = URL(fileURLWithPath: "/Users/me/A/-dash.txt")
        let b = URL(fileURLWithPath: "/Users/me/B/@list")
        let plan = try XCTUnwrap(CompressPlan.make(for: [a, b]))
        let out = URL(fileURLWithPath: "/Users/me/A/.w.zip")
        XCTAssertEqual(plan.command(writingTo: out).arguments,
                       ["-a", "-c", "-f", out.path, "-C", "/Users/me/A", "./-dash.txt", "-C", "/Users/me/B", "./@list"])
        XCTAssertEqual(plan.sharedNames, [])
        let shared = try XCTUnwrap(CompressPlan.make(for: [URL(fileURLWithPath: "/Users/me/A/x.pdf"), URL(fileURLWithPath: "/Users/me/B/X.pdf")]))
        XCTAssertEqual(shared.sharedNames, ["X.pdf"])
    }

    // MARK: Put Back

    /// A .DS_Store as Finder writes one: the buddy-allocator header, a root
    /// block with the block table and the "DSDB" entry, the B-tree's header
    /// block and one leaf of "ustr" records.
    static func dsStore(_ records: [(file: String, code: String, text: String)]) -> Data {
        func u32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }
        func utf16(_ s: String) -> [UInt8] { s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } }
        var leaf = u32(0) + u32(records.count)
        for record in records {
            leaf += u32(record.file.utf16.count) + utf16(record.file) + Array(record.code.utf8) + Array("ustr".utf8)
            leaf += u32(record.text.utf16.count) + utf16(record.text)
        }
        let header = u32(1) + u32(0) + u32(records.count) + u32(1) + u32(0x1000)
        let (headerAt, rootAt, leafAt) = (64, 2048, 4096)
        var root = u32(2) + u32(0) + u32(headerAt | 5) + u32(leafAt | 12)
        root += [UInt8](repeating: 0, count: 4 * 254)
        root += u32(1) + [4] + Array("DSDB".utf8) + u32(0)
        root += [UInt8](repeating: 0, count: 32 * 4)
        var file = [UInt8](repeating: 0, count: 4 + 8192)
        func put(_ bytes: [UInt8], at offset: Int) { file.replaceSubrange((offset)..<(offset + bytes.count), with: bytes) }
        put([0, 0, 0, 1], at: 0)
        put(Array("Bud1".utf8) + u32(rootAt) + u32(2048) + u32(rootAt), at: 4)
        put(header, at: 4 + headerAt)
        put(root, at: 4 + rootAt)
        put(leaf, at: 4 + leafAt)
        return Data(file)
    }

    func testFindersPutBackRecordsAreRead() throws {
        let data = Self.dsStore([
            ("Report 10.42.13.pdf", "ptbL", "Users/me/Documents/"),
            ("Report 10.42.13.pdf", "ptbN", "Report.pdf"),
            ("photo.jpg", "ptbL", "Users/me/Desktop/"),
        ])
        let records = FinderPutBack.records(in: data)
        XCTAssertEqual(records["Report 10.42.13.pdf"], FinderPutBack.Record(folder: "Users/me/Documents/", name: "Report.pdf"))
        XCTAssertEqual(records["photo.jpg"], FinderPutBack.Record(folder: "Users/me/Desktop/", name: "photo.jpg"), "no ptbN: the name it has")

        let trash = try temp.folder("Trash")
        try data.write(to: trash.appendingPathComponent(".DS_Store"))
        let originals = FinderPutBack.originals(trash: trash, volumeRoot: temp.root)
        let key = trash.appendingPathComponent("Report 10.42.13.pdf").standardizedFileURL.path
        XCTAssertEqual(originals[key]?.path, temp.root.appendingPathComponent("Users/me/Documents/Report.pdf").path)
    }

    func testADamagedDSStoreGivesNothing() {
        var bytes = [UInt8](Self.dsStore([("a", "ptbL", "x/")]))
        XCTAssertEqual(FinderPutBack.records(in: Data(bytes)).count, 1)
        for cut in [0, 7, 40, 2100, 4110] { XCTAssertEqual(FinderPutBack.records(in: Data(bytes.prefix(cut))), [:]) }
        bytes[4 + 4096 + 7] = 200 // a record count far past the block
        XCTAssertEqual(FinderPutBack.records(in: Data(bytes)), [:])
        XCTAssertEqual(FinderPutBack.records(in: Data(repeating: 0xff, count: 5000)), [:])
    }

    func testTheLedgerIgnoresAnItemThatTookATrashedItemsName() throws {
        let trashed = try temp.file("Trash/r.pdf", "from A")
        var ledger = TrashLedger()
        ledger.apply(.trashed(original: URL(fileURLWithPath: "/Users/me/A/r.pdf"), trashed: trashed, stamp: FileStamp.of(trashed)))
        XCTAssertEqual(ledger.original(of: trashed)?.path, "/Users/me/A/r.pdf")
        // Undone, then another r.pdf trashed by Finder lands on the same name.
        try FileManager.default.moveItem(at: trashed, to: temp.url("r.pdf"))
        try temp.file("Trash/r.pdf", "from B")
        XCTAssertNil(ledger.original(of: trashed), "the new item is not sent to A")
        ledger.apply(.left(trashed: trashed))
        XCTAssertTrue(ledger.entries.isEmpty)
    }

    func testOldLedgersStillRead() throws {
        let old = Data(#"{"entries":{"/Users/me/.Trash/a.pdf":"/Users/me/Documents/a.pdf"}}"#.utf8)
        let ledger = try JSONDecoder().decode(TrashLedger.self, from: old)
        XCTAssertEqual(ledger.original(of: URL(fileURLWithPath: "/Users/me/.Trash/a.pdf"))?.path, "/Users/me/Documents/a.pdf")
        let again = try JSONDecoder().decode(TrashLedger.self, from: try JSONEncoder().encode(ledger))
        XCTAssertEqual(again, ledger)
    }

    // MARK: Apply to All

    func testApplyToAllCoversOnlyTheListedConflicts() async {
        let folder = URL(fileURLWithPath: "/Users/me/Documents")
        let conflicts = ["a.txt", "b.txt"].map {
            FileConflict(source: URL(fileURLWithPath: "/Users/me/Downloads/" + $0), existing: folder.appendingPathComponent($0))
        }
        let resolution = await ConflictQuestions.resolve(conflicts) { _, _ in ConflictAnswer(.replace, applyToAll: true) }
        XCTAssertEqual(resolution?.policy(for: "a.txt"), .replace)
        XCTAssertEqual(resolution?.policy(for: "b.txt"), .replace)
        XCTAssertEqual(resolution?.policy(for: "c.txt"), .keepBoth, "a name taken later is never replaced unasked")
    }

    // MARK: Tab with one pane

    func testTabSelectsTheNextItemByName() {
        let rows = [(id: "3", name: "b.txt"), (id: "1", name: "a.txt"), (id: "2", name: "C.txt"), (id: "4", name: "file10"), (id: "5", name: "file9")]
        XCTAssertEqual(TabSelect.target(items: rows, selected: [], backwards: false), "1")
        XCTAssertEqual(TabSelect.target(items: rows, selected: [], backwards: true), "4")
        XCTAssertEqual(TabSelect.target(items: rows, selected: ["1"], backwards: false), "3")
        XCTAssertEqual(TabSelect.target(items: rows, selected: ["3"], backwards: false), "2", "by name, not by the sort")
        XCTAssertEqual(TabSelect.target(items: rows, selected: ["2"], backwards: false), "5", "file9 before file10, as Finder orders")
        XCTAssertEqual(TabSelect.target(items: rows, selected: ["1"], backwards: true), "4", "goes round")
        XCTAssertNil(TabSelect.target(items: [], selected: [], backwards: false))
    }

    // MARK: Which folders get sizes

    func testSizesAreMeasuredForFoldersOnScreen() {
        let rows = (0..<100).map { item("F\($0)", folder: true) } + [item("a.pdf")]
        XCTAssertEqual(SizeScope.folders(rows, visible: [], sortedBySize: false).count, SizeScope.firstScreen)
        let shown = Set(rows[10..<15].map(\.id))
        XCTAssertEqual(SizeScope.folders(rows, visible: shown, sortedBySize: false).map(\.lastPathComponent), ["F10", "F11", "F12", "F13", "F14"])
        XCTAssertEqual(SizeScope.folders(rows, visible: shown, sortedBySize: true).count, 100, "sorting by size needs them all")
        var prefs = NexusPreferences()
        XCTAssertTrue(prefs.calculateFolderSizes)
        XCTAssertFalse(prefs.folderSizeLimits.includeRemote, "network and cloud folders only when chosen")
        prefs.remoteFolderSizes = true
        XCTAssertTrue(prefs.folderSizeLimits.includeRemote)
    }
}
