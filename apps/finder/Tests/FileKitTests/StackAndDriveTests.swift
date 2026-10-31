import XCTest
@testable import FileKit

final class StackAndDriveTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box.remove()
    }

    // MARK: Version stacks

    func testFamilyNames() {
        for name in [
            "Report.docx", "Report v01.docx", "Report_v2.docx", "report-V3.docx", "Report final.docx",
            "Report_FINAL2.docx", "Report final 2.docx", "Report copy.docx", "Report copy 2.docx",
            "Report (1).docx", "Report(2).docx", "Report 2026-10-31.docx", "Report_20261031.docx",
            "2026-10-31 Report.docx", "Report v2 final.docx", "Report_final_final.docx",
        ] {
            XCTAssertEqual(VersionStack.family(of: name), "report.docx", name)
        }
    }

    func testNamesThatAreNotVersions() {
        XCTAssertEqual(VersionStack.family(of: "Chapter 2.docx"), "chapter 2.docx")
        XCTAssertEqual(VersionStack.family(of: "Semifinal.docx"), "semifinal.docx")
        XCTAssertEqual(VersionStack.family(of: "final.docx"), "final.docx")
        XCTAssertEqual(VersionStack.family(of: "Report 2026-13-40.docx"), "report 2026-13-40.docx")
        XCTAssertEqual(VersionStack.family(of: "Report v2.pdf"), "report.pdf")
        XCTAssertEqual(VersionStack.family(of: "Notes"), "notes")
    }

    func testStacksGroupUnderTheNewest() {
        let folder = URL(fileURLWithPath: "/Users/me/Docs")
        func item(_ name: String, _ day: Double) -> (url: URL, modified: Date) {
            (folder.appendingPathComponent(name), Date(timeIntervalSince1970: day * 86_400))
        }
        let stacks = VersionStack.stacks(for: [
            item("Report v01.docx", 1),
            item("Budget.xlsx", 2),
            item("Report final.docx", 5),
            item("Report v02.docx", 3),
            item("Report.pdf", 4),
        ])
        XCTAssertEqual(stacks.map(\.newest.lastPathComponent), ["Report final.docx", "Budget.xlsx", "Report.pdf"])
        XCTAssertEqual(stacks[0].older.map(\.lastPathComponent), ["Report v02.docx", "Report v01.docx"])
        XCTAssertEqual(stacks[0].all.count, 3)
        XCTAssertTrue(stacks[1].older.isEmpty)
    }

    func testOtherFoldersAreSeparateStacks() {
        let stacks = VersionStack.stacks(for: [
            (URL(fileURLWithPath: "/a/Plan v1.md"), Date(timeIntervalSince1970: 1)),
            (URL(fileURLWithPath: "/b/Plan v2.md"), Date(timeIntervalSince1970: 2)),
        ])
        XCTAssertEqual(stacks.count, 2)
    }

    func testStacksReadDatesFromDisk() throws {
        let old = try box.file("v/Plan v1.md")
        let new = try box.file("v/Plan v2.md")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path)
        let stacks = VersionStack.stacks(for: [old, new])
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].newest.lastPathComponent, "Plan v2.md")
    }

    // MARK: Google Drive

    private func fakeHome() throws -> URL {
        try box.folder("home/Library/CloudStorage/GoogleDrive-me@example.com/My Drive/Papers")
        try box.folder("home/Library/CloudStorage/GoogleDrive-other@example.com/My Drive")
        try box.folder("home/Library/CloudStorage/OneDrive-Personal")
        try box.folder("home/Desktop")
        try FileManager.default.createSymbolicLink(
            at: box.url("home/Drive"),
            withDestinationURL: box.url("home/Library/CloudStorage/GoogleDrive-me@example.com/My Drive")
        )
        return box.url("home")
    }

    func testFindsAccounts() throws {
        let home = try fakeHome()
        let drives = GoogleDrive.accounts(home: home)
        XCTAssertEqual(drives.map(\.account), ["me@example.com", "other@example.com"])
        XCTAssertEqual(drives[0].myDrive.lastPathComponent, "My Drive")
        XCTAssertEqual(drives[0].sharedDrives.lastPathComponent, "Shared drives")
        XCTAssertTrue(GoogleDrive.accounts(home: box.url("nowhere")).isEmpty)
    }

    func testContainsFollowsLinks() throws {
        let home = try fakeHome()
        let drive = try XCTUnwrap(GoogleDrive.accounts(home: home).first)
        XCTAssertTrue(drive.contains(drive.myDrive.appendingPathComponent("Papers")))
        XCTAssertTrue(drive.contains(home.appendingPathComponent("Drive/Papers")))
        XCTAssertFalse(drive.contains(home.appendingPathComponent("Desktop")))
        XCTAssertEqual(GoogleDrive.drive(containing: home.appendingPathComponent("Drive"), home: home), drive)
        XCTAssertNil(GoogleDrive.drive(containing: home.appendingPathComponent("Desktop"), home: home))
    }

    func testDraggingOutOfDriveCopies() throws {
        let home = try fakeHome()
        let drives = GoogleDrive.accounts(home: home)
        let paper = drives[0].myDrive.appendingPathComponent("Papers")
        let desktop = home.appendingPathComponent("Desktop")
        XCTAssertEqual(GoogleDrive.dragOperation(from: [paper], to: desktop, home: home), .copy)
        XCTAssertEqual(GoogleDrive.dragOperation(from: [paper], to: drives[1].myDrive, home: home), .copy)
        XCTAssertEqual(GoogleDrive.dragOperation(from: [paper], to: drives[0].myDrive, home: home), .move)
        XCTAssertEqual(GoogleDrive.dragOperation(from: [desktop], to: drives[0].myDrive, home: home), .move)
        XCTAssertEqual(GoogleDrive.dragOperation(from: [desktop], to: home, home: home), .move)
    }
}
