import ArchiveKit
import LaunchKit
import XCTest
@testable import BrowserKit

/// R26 (archives as folders, partial extract) and R19 (the file viewer).
final class ArchiveAndTakeoverTests: XCTestCase {
    func testArchiveRowsAndPartialExtract() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/bsdtar"))
        let temp = try TempFolder()
        defer { temp.remove() }
        try temp.file("src/Figures/plot.png", "png")
        try temp.file("src/README.md", "readme")
        let zip = temp.url("Data.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["-a", "-c", "-f", zip.path, "-C", temp.url("src").path, "Figures", "README.md"]
        try process.run()
        process.waitUntilExit()

        let listing = try Archive.list(zip)
        let top = try XCTUnwrap(ArchiveRows.items(in: listing, at: ""))
        XCTAssertEqual(top.map(\.name), ["Figures", "README.md"])
        XCTAssertTrue(top[0].isFolder)
        XCTAssertEqual(top[1].archiveEntry, "README.md")
        XCTAssertEqual(top[1].url.path, zip.path + "/README.md")
        XCTAssertNil(ArchiveRows.items(in: listing, at: "README.md"), "a file is not a folder")
        let inner = try XCTUnwrap(ArchiveRows.items(in: listing, at: "Figures"))
        XCTAssertEqual(inner.map(\.archiveEntry), ["Figures/plot.png"])

        let out = try temp.folder("out")
        let made = try Archive.extract(ArchiveRows.entries([inner[0]]), from: zip, to: out)
        XCTAssertEqual(made.map(\.lastPathComponent), ["plot.png"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.appendingPathComponent("README.md").path), "only the selection")
    }

    func testOpenFoldersAndRevealFiles() {
        let a = URL(fileURLWithPath: "/Users/me/Documents/a.pdf")
        let b = URL(fileURLWithPath: "/Users/me/Documents/b.pdf")
        let c = URL(fileURLWithPath: "/Users/me/Desktop/c.pdf")
        let folder = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
        let isFolder: (URL) -> Bool = { $0.hasDirectoryPath }

        let reveal = ViewerRouting.windows(for: .reveal([a, c, b]), isFolder: isFolder)
        XCTAssertEqual(reveal, [
            WindowRequest(folder: URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true), select: [a, b]),
            WindowRequest(folder: URL(fileURLWithPath: "/Users/me/Desktop", isDirectory: true), select: [c]),
        ])

        let open = ViewerRouting.windows(for: .open([folder, a]), isFolder: isFolder)
        XCTAssertEqual(open.first, WindowRequest(folder: folder))
        XCTAssertEqual(open.last?.select, [a], "a file handed to open is shown selected")
    }
}
