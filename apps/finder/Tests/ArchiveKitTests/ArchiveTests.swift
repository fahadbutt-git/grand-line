import XCTest
@testable import ArchiveKit

final class ArchiveTests: XCTestCase {
    private var space: Workspace!

    override func setUpWithError() throws {
        space = try Workspace()
        try space.file("src/README.md", "read me")
        try space.file("src/Figures/plot one.png", "png bytes")
        try space.file("src/Figures/raw/data.csv", "a,b\n1,2\n")
        try space.file("src/odd [name]*.txt", "odd")
    }

    override func tearDown() {
        space.remove()
    }

    func testListsAZipAsATree() throws {
        let listing = try Archive.list(try space.zip("src", to: "bundle.zip"))
        XCTAssertEqual(listing.root.children.map(\.name), ["Figures", "odd [name]*.txt", "README.md"])
        let figures = try XCTUnwrap(listing.item(at: "Figures"))
        XCTAssertTrue(figures.isFolder)
        XCTAssertEqual(figures.children.map(\.name), ["raw", "plot one.png"])
        XCTAssertEqual(listing.item(at: "Figures/raw/data.csv")?.size, 8)
        XCTAssertEqual(figures.size, 17)
        XCTAssertNotNil(listing.item(at: "README.md")?.modified)
        XCTAssertNil(listing.item(at: "nope"))
        XCTAssertTrue(listing.rejected.isEmpty)
    }

    func testListsCompressedTars() throws {
        for name in ["bundle.tar", "bundle.tar.gz", "bundle.tar.bz2", "bundle.tar.xz"] {
            let listing = try Archive.list(try space.tar("src", to: name))
            XCTAssertEqual(listing.item(at: "Figures/plot one.png")?.size, 9, name)
            XCTAssertEqual(listing.item(at: "./README.md")?.name, "README.md", name)
            XCTAssertTrue(listing.rejected.isEmpty, name)
        }
    }

    func testExtractOneFile() throws {
        let archive = try space.zip("src", to: "bundle.zip")
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let results = try Archive.extract(["Figures/raw/data.csv"], from: archive, to: out)
        XCTAssertEqual(results.map(\.lastPathComponent), ["data.csv"])
        XCTAssertEqual(space.text(out.appendingPathComponent("data.csv")), "a,b\n1,2\n")
        let again = try Archive.extract(["Figures/raw/data.csv"], from: archive, to: out)
        XCTAssertEqual(again.map(\.lastPathComponent), ["data 2.csv"])
        let left = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(left, ["data 2.csv", "data.csv"])
    }

    func testExtractAFolder() throws {
        let archive = try space.tar("src", to: "bundle.tgz")
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Archive.extract(["Figures"], from: archive, to: out)
        XCTAssertEqual(space.text(out.appendingPathComponent("Figures/plot one.png")), "png bytes")
        XCTAssertEqual(space.text(out.appendingPathComponent("Figures/raw/data.csv")), "a,b\n1,2\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("README.md").path))
    }

    func testNamesWithPatternCharacters() throws {
        let archive = try space.zip("src", to: "bundle.zip")
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Archive.extract(["odd [name]*.txt"], from: archive, to: out)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertEqual(names, ["odd [name]*.txt"])
    }

    func testPreviewGoesToATemporaryFolder() throws {
        let archive = try space.zip("src", to: "bundle.zip")
        let preview = try Archive.preview("README.md", from: archive)
        XCTAssertEqual(space.text(preview), "read me")
        XCTAssertTrue(preview.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        try? FileManager.default.removeItem(at: preview.deletingLastPathComponent())
    }

    func testTraversalIsRejected() throws {
        let archive = try space.handmadeTar(
            [("../evil.txt", "bad"), ("/abs.txt", "bad"), ("good.txt", "fine")], to: "evil.tar"
        )
        let listing = try Archive.list(archive)
        XCTAssertEqual(listing.root.children.map(\.name), ["good.txt"])
        XCTAssertEqual(listing.rejected, ["../evil.txt", "/abs.txt"])
        let out = space.url("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for bad in ["../evil.txt", "/abs.txt"] {
            XCTAssertThrowsError(try Archive.extract([bad], from: archive, to: out)) { error in
                XCTAssertEqual(error as? ArchiveError, .unsafePath(bad))
            }
        }
        XCTAssertThrowsError(try Archive.extract(["missing.txt"], from: archive, to: out)) { error in
            XCTAssertEqual(error as? ArchiveError, .notInArchive("missing.txt"))
        }
        try Archive.extract(["good.txt"], from: archive, to: out)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["good.txt"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: space.url("evil.txt").path))
    }

    func testPathRules() {
        XCTAssertTrue(ArchivePath.isSafe("a/b.txt"))
        XCTAssertTrue(ArchivePath.isSafe("./a/b.txt"))
        XCTAssertTrue(ArchivePath.isSafe("a..b/c"))
        XCTAssertFalse(ArchivePath.isSafe("../a"))
        XCTAssertFalse(ArchivePath.isSafe("a/../../b"))
        XCTAssertFalse(ArchivePath.isSafe("a\\..\\b"))
        XCTAssertFalse(ArchivePath.isSafe("/etc/passwd"))
        XCTAssertFalse(ArchivePath.isSafe("C:/x"))
        XCTAssertFalse(ArchivePath.isSafe(""))
        XCTAssertTrue(ArchivePath.isMacMetadata("__MACOSX/a/._b.txt"))
        XCTAssertTrue(ArchivePath.isMacMetadata("a/._b.txt"))
        XCTAssertTrue(ArchivePath.isMacMetadata("a/.DS_Store"))
        XCTAssertFalse(ArchivePath.isMacMetadata("a/b.txt"))
        XCTAssertFalse(ArchivePath.isMacMetadata("MACOSX notes/a.txt"))
        XCTAssertFalse(ArchivePath.isSafe("./"))
        XCTAssertEqual(ArchivePath.normalize("./a//b/./c/"), "a/b/c")
        XCTAssertEqual(ArchivePath.pattern("a*[b]?\\"), "a\\*\\[b]\\?\\\\")
    }

    func testIsArchive() {
        for name in ["a.zip", "b.7z", "c.RAR", "d.tar", "e.tgz", "f.tar.gz", "g.tar.bz2", "h.tar.xz", "i.txz"] {
            XCTAssertTrue(Archive.isArchive(URL(fileURLWithPath: "/x/" + name)), name)
        }
        for name in ["a.docx", "zip", ".zip", "notes.txt"] {
            XCTAssertFalse(Archive.isArchive(URL(fileURLWithPath: "/x/" + name)), name)
        }
    }

    func testUnescapingAndParsing() {
        XCTAssertEqual(BsdTar.unescape("a\\\\b"), "a\\b")
        XCTAssertEqual(BsdTar.unescape("line\\nbreak"), "line\nbreak")
        XCTAssertEqual(BsdTar.unescape("caf\\303\\251"), "café")
        let entry = ArchiveEntry.parse(
            verbose: "-rw-r--r--  0 me     staff     1234 Oct 31  2025 Folder/file name.txt",
            name: "Folder/file name.txt"
        )
        XCTAssertEqual(entry.size, 1234)
        XCTAssertFalse(entry.isFolder)
        XCTAssertNotNil(entry.modified)
        let folder = ArchiveEntry.parse(verbose: "drwxr-xr-x  0 me staff 0 Oct 31 12:00 Folder/", name: "Folder/")
        XCTAssertTrue(folder.isFolder)
    }

    func testFiveThousandEntries() throws {
        for i in 0..<5_000 {
            let folder = space.url("many/group \(i % 50)")
            if i < 50 { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
            FileManager.default.createFile(atPath: folder.appendingPathComponent("item \(i).txt").path, contents: Data("\(i)".utf8))
        }
        let archive = try space.tar("many", to: "many.tar")
        let start = Date()
        let listing = try Archive.list(archive)
        print("listed 5,000 entries in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        XCTAssertEqual(listing.root.children.count, 50)
        XCTAssertEqual(listing.item(at: "group 7")?.children.count, 100)
        XCTAssertEqual(listing.item(at: "group 7/item 4507.txt")?.size, 4)
    }
}
