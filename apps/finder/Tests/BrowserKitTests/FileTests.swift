import FileKit
import XCTest
@testable import BrowserKit

/// R10, R11, R21: reading folders, Put Back, compress, aliases, tags, comments.
final class FileTests: XCTestCase {
    private var temp: TempFolder!

    override func setUpWithError() throws {
        temp = try TempFolder()
    }

    override func tearDown() {
        temp.remove()
    }

    func testTheTrashIsTheFixtureHomesAndTheAccountsOwn() {
        let paths = AppPaths(home: URL(fileURLWithPath: "/tmp/fixture-home", isDirectory: true))
        XCTAssertTrue(paths.isTrash(URL(fileURLWithPath: "/tmp/fixture-home/.Trash", isDirectory: true)))
        XCTAssertTrue(paths.isTrash(AppPaths.accountTrash))
        XCTAssertFalse(paths.isTrash(URL(fileURLWithPath: "/tmp/fixture-home/Documents", isDirectory: true)))
    }

    func testFolderReaderHidesClutterAlways() throws {
        try temp.file("Share/report.pdf")
        try temp.file("Share/.DS_Store")
        try temp.file("Share/._report.pdf")
        try temp.file("Share/.env")
        try temp.folder("Share/Figures")
        let folder = temp.url("Share")
        XCTAssertEqual(try FolderReader.items(in: folder, showHidden: false).map(\.name).sorted(), ["Figures", "report.pdf"])
        XCTAssertEqual(try FolderReader.items(in: folder, showHidden: true).map(\.name).sorted(), [".env", "Figures", "report.pdf"])
        XCTAssertEqual(FolderReader.subfolderNames(folder), ["Figures"])
    }

    func testAFolderOpenedThroughALinkListsItsTargetUnderTheLinksPath() throws {
        try temp.file("Safety/Real/report.pdf", "report")
        try temp.folder("Safety/Real/sub")
        let link = temp.url("Safety/Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temp.url("Safety/Real"))
        let chain = temp.url("Safety/Chain")
        try FileManager.default.createSymbolicLink(atPath: chain.path, withDestinationPath: "Link")

        XCTAssertEqual(FolderReader.listingTarget(temp.url("Safety/Real")), temp.url("Safety/Real"), "a real folder is read as it is")
        // Resolved the same way (it also drops /private before /var).
        let real = temp.url("Safety/Real").resolvingSymlinksInPath().path
        XCTAssertEqual(FolderReader.listingTarget(link).path, real)
        XCTAssertEqual(FolderReader.listingTarget(chain).path, real, "a link to a link")
        for folder in [link, chain] {
            let items = try FolderReader.items(in: folder, showHidden: false)
            XCTAssertEqual(items.map(\.name).sorted(), ["report.pdf", "sub"], folder.lastPathComponent)
            let report = try XCTUnwrap(items.first { $0.name == "report.pdf" })
            XCTAssertEqual(report.url.deletingLastPathComponent().lastPathComponent, folder.lastPathComponent, "shown through the link")
            XCTAssertFalse(report.isFolder)
            XCTAssertEqual(report.size, 6)
            XCTAssertTrue(try XCTUnwrap(items.first { $0.name == "sub" }).isFolder)
            XCTAssertEqual(FolderReader.subfolderNames(folder), ["sub"])
        }
    }

    func testItemsReadFromDisk() throws {
        let url = try temp.file("notes.md", "hello")
        let read = try XCTUnwrap(FileItem.read(url))
        XCTAssertEqual(read.size, 5)
        XCTAssertFalse(read.isFolder)
        XCTAssertEqual(read.ext, "md")
        XCTAssertNil(FileItem.read(temp.url("missing")))
        XCTAssertNil(try XCTUnwrap(FileItem.read(temp.root)).size, "folder sizes come from FolderSize")
    }

    func testTrashLedgerPutsBack() {
        var ledger = TrashLedger()
        let original = URL(fileURLWithPath: "/Users/me/Documents/Report.pdf")
        let trashed = URL(fileURLWithPath: "/Users/me/.Trash/Report 10.42.13.pdf")
        ledger.record(originals: [original], trashed: [trashed])
        XCTAssertTrue(ledger.canPutBack([trashed]))
        XCTAssertEqual(ledger.destination(of: trashed)?.folder.path, "/Users/me/Documents")
        XCTAssertEqual(ledger.destination(of: trashed)?.name, "Report.pdf")
        ledger.prune { _ in false }
        XCTAssertFalse(ledger.canPutBack([trashed]))
    }

    func testPutBackThroughFileKit() async throws {
        let original = try temp.file("Documents/Report.pdf")
        let trashFolder = try temp.folder("Trash")
        let operations = FileOperations(trash: { url in
            let destination = trashFolder.appendingPathComponent("Report 10.42.13.pdf")
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        let trashed = try await operations.moveToTrash([original])
        var ledger = TrashLedger()
        ledger.record(originals: [original], trashed: trashed)
        let place = try XCTUnwrap(ledger.destination(of: trashed[0]))
        let moved = try await operations.move(trashed, to: place.folder)
        _ = try await operations.rename(moved[0], to: place.name)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testCompressPlans() throws {
        let a = try temp.file("a.txt")
        let b = try temp.file("b.txt")
        let out = temp.url("out.zip")
        let one = try XCTUnwrap(CompressPlan.make(for: [a]))
        XCTAssertEqual(one.name, "a.txt.zip")
        XCTAssertEqual(one.folder.standardizedFileURL, temp.root.standardizedFileURL)
        XCTAssertEqual(one.command(writingTo: out).executable, "/usr/bin/ditto")
        XCTAssertEqual(one.command(writingTo: out).arguments.last, out.path)
        let many = try XCTUnwrap(CompressPlan.make(for: [a, b]))
        XCTAssertEqual(many.name, "Archive.zip")
        XCTAssertEqual(Array(many.command(writingTo: out).arguments.suffix(2)), [temp.root.path, "b.txt"])
        XCTAssertNil(CompressPlan.make(for: []))
    }

    func testCompressMakesAZip() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/bsdtar"))
        let a = try temp.file("a.txt")
        let b = try temp.file("b.txt")
        let plan = try XCTUnwrap(CompressPlan.make(for: [a, b]))
        let made = try await Compressor.run(plan, operations: FileOperations(trash: { $0 }))
        XCTAssertEqual(made.lastPathComponent, "Archive.zip")
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: made.path)[.size] as? Int) ?? 0, 0)
    }

    func testAliasPointsToTheOriginal() throws {
        let original = try temp.file("Protocol.pdf")
        let alias = try AliasFile.make(for: original)
        XCTAssertEqual(alias.lastPathComponent, "Protocol.pdf alias")
        XCTAssertEqual(AliasFile.original(of: alias)?.standardizedFileURL.resolvingSymlinksInPath().path,
                       original.standardizedFileURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(AliasFile.name(for: original, in: temp.root), "Protocol.pdf alias 2")
        XCTAssertNil(AliasFile.original(of: original))
    }

    func testTagToggleLikeFinder() {
        XCTAssertEqual(TagEditor.toggling("Red", in: [["Red"], []]), [["Red"], ["Red"]], "not all have it: all get it")
        XCTAssertEqual(TagEditor.toggling("Red", in: [["Red", "Blue"], ["Red"]]), [["Blue"], []], "all have it: it comes off")
        XCTAssertEqual(TagEditor.color(for: .tagGreen), "Green")
        XCTAssertNil(TagEditor.color(for: .open))
    }

    func testInspectorTagEdits() {
        XCTAssertEqual(TagEditor.applying(common: ["Urgent"], edited: ["Review"], to: ["Urgent", "Blue"]), ["Blue", "Review"])
        XCTAssertEqual(TagEditor.parse(" urgent, Review ,urgent,, "), ["urgent", "Review"])
    }

    func testTagsAndCommentsAreWritten() throws {
        let url = try temp.file("paper.pdf")
        try TagEditor.write(["Submission", "Red"], to: url)
        XCTAssertEqual(Set(TagEditor.read(url)), ["Submission", "Red"])
        try FinderComment.write("Second round", to: url)
        XCTAssertEqual(FinderComment.read(url), "Second round")
        try FinderComment.write("", to: url)
        XCTAssertEqual(FinderComment.read(url), "")
    }

    func testSelectionFile() throws {
        let file = SelectionFile(url: temp.url("state/nexus-selection"))
        let zip = URL(fileURLWithPath: "/Users/me/Data.zip")
        file.write([item("a.pdf"), item("b.pdf"), FileItem(url: zip.appendingPathComponent("x"), name: "x", isFolder: false, archiveEntry: "x")])
        XCTAssertEqual(file.read(), ["/Users/me/Documents/a.pdf", "/Users/me/Documents/b.pdf"])
        XCTAssertEqual(String(decoding: try Data(contentsOf: file.url), as: UTF8.self), "/Users/me/Documents/a.pdf\n/Users/me/Documents/b.pdf\n")
        file.write([])
        XCTAssertEqual(file.read(), [])
        XCTAssertEqual(SelectionFile.contents([]), "")
    }

    func testClutterIsFoundForTheCleaner() throws {
        // "._" files are hidden on the Mac's own disk, so the disk check uses .DS_Store.
        try temp.file("Drive/.DS_Store")
        try temp.file("Drive/sub/.DS_Store")
        try temp.file("Drive/sub/a")
        XCTAssertEqual(try Clutter.find(in: temp.url("Drive")).count, 2)
    }
}
