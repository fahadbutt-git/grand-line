import FileKit
import UniformTypeIdentifiers
import XCTest
@testable import BrowserKit

/// R9, R10, R14, R20: what rows, the footer and the inspector say.
final class FormatTests: XCTestCase {
    func testSizesAreFinderStyle() {
        XCTAssertEqual(ItemFormat.size(412_000), ByteCountFormatter.string(fromByteCount: 412_000, countStyle: .file))
        XCTAssertEqual(ItemFormat.count(1), "1 item")
        XCTAssertEqual(ItemFormat.count(14), "14 items")
        XCTAssertEqual(ItemFormat.status(selected: 0, total: 9, selectedBytes: nil), "9 items")
        XCTAssertTrue(ItemFormat.status(selected: 3, total: 9, selectedBytes: 18_600_000).hasPrefix("3 of 9 selected · "))
        XCTAssertTrue(ItemFormat.free(1_620_000_000_000).hasSuffix(" free"))
    }

    func testRelativeDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(ItemFormat.date(now, now: now, calendar: calendar, locale: locale).hasPrefix("Today, "))
        XCTAssertTrue(ItemFormat.date(now.addingTimeInterval(-86_400), now: now, calendar: calendar, locale: locale).hasPrefix("Yesterday, "))
        let older = ItemFormat.date(now.addingTimeInterval(-86_400 * 30), now: now, calendar: calendar, locale: locale)
        XCTAssertFalse(older.hasPrefix("Today") || older.hasPrefix("Yesterday"))
    }

    func testDriveBadges() {
        XCTAssertNil(DriveBadge.badge(inDrive: false, status: .notDownloaded, isDownloading: false))
        XCTAssertEqual(DriveBadge.badge(inDrive: true, status: .notDownloaded, isDownloading: false), .online)
        XCTAssertEqual(DriveBadge.badge(inDrive: true, status: .current, isDownloading: false), .downloaded)
        XCTAssertEqual(DriveBadge.badge(inDrive: true, status: nil, isDownloading: true), .downloading)
        XCTAssertEqual(DriveBadge.online.symbol, "icloud")
    }

    func testDraggingOutOfDriveCopies() throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let file = try temp.file("Library/CloudStorage/GoogleDrive-smith@example.com/My Drive/notes.md")
        let desktop = try temp.folder("Desktop")
        XCTAssertEqual(GoogleDrive.dragOperation(from: [file], to: desktop, home: temp.root), .copy)
    }

    func testSymbolsAreSFSymbolNames() {
        XCTAssertEqual(FileSymbol.name(for: item("Papers", folder: true)), "folder")
        XCTAssertEqual(FileSymbol.name(for: item("Downloads", folder: true)), "arrow.down.circle")
        XCTAssertEqual(FileSymbol.name(for: item("data.csv")), "tablecells")
        let pdf = FileItem(url: documents.appendingPathComponent("a.pdf"), name: "a.pdf", isFolder: false, typeIdentifier: UTType.pdf.identifier)
        XCTAssertEqual(FileSymbol.name(for: pdf), "doc.richtext")
        XCTAssertEqual(FileSymbol.name(for: item("model.R")), "chevron.left.forwardslash.chevron.right")
    }

    func testInspectorRows() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let a = try temp.file("Submission/a.txt", "12345")
        let b = try temp.file("Submission/b.txt", "123")
        let summary = await SelectionSummary.make(for: [a, b])
        XCTAssertEqual(InspectorRows.title(summary, single: nil), "2 items selected")
        XCTAssertTrue(InspectorRows.size(summary).hasSuffix(" in total"))
        let labels = InspectorRows.rows(summary, home: temp.root).map(\.label)
        XCTAssertEqual(labels, ["Kinds", "Where", "Oldest", "Newest"])
        let one = await SelectionSummary.make(for: [a])
        XCTAssertEqual(InspectorRows.title(one, single: FileItem.read(a)), "a.txt")
    }
}
