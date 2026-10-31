import FileKit
import XCTest
@testable import BrowserKit

/// Rename N Items: Finder's three modes, a regular expression and case, with
/// a live preview that refuses clashes before anything changes.
final class BatchRenameTests: XCTestCase {
    let folder = URL(fileURLWithPath: "/Users/me/Pictures/Trip", isDirectory: true)
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    func urls(_ names: [String]) -> [URL] { names.map { folder.appendingPathComponent($0) } }

    func testReplaceTextKeepsTheExtension() {
        var rename = BatchRename()
        rename.find = "img"
        rename.replacement = "Photo"
        XCTAssertEqual(rename.newName(for: "IMG_0001.jpg", index: 0), "Photo_0001.jpg")
        rename.matchCase = true
        XCTAssertEqual(rename.newName(for: "IMG_0001.jpg", index: 0), "IMG_0001.jpg")
        rename.matchCase = false
        rename.find = "jpg"
        XCTAssertEqual(rename.newName(for: "jpg notes.jpg", index: 0), "Photo notes.jpg", "the extension is left alone")
        rename.includeExtension = true
        XCTAssertEqual(rename.newName(for: "jpg notes.jpg", index: 0), "Photo notes.Photo")
    }

    func testAddTextBeforeOrAfter() {
        var rename = BatchRename()
        rename.mode = .add
        rename.addText = "final "
        rename.addPosition = .before
        XCTAssertEqual(rename.newName(for: "report.pdf", index: 0), "final report.pdf")
        rename.addText = " v2"
        rename.addPosition = .after
        XCTAssertEqual(rename.newName(for: "report.pdf", index: 0), "report v2.pdf")
    }

    func testFormatsNumberFromTheStart() {
        var rename = BatchRename()
        rename.mode = .format
        rename.customFormat = "Trip"
        rename.startAt = 5
        XCTAssertEqual(rename.newName(for: "a.jpg", index: 0), "Trip5.jpg")
        XCTAssertEqual(rename.newName(for: "b.jpg", index: 2), "Trip7.jpg")
        rename.format = .counter
        XCTAssertEqual(rename.newName(for: "a.jpg", index: 0), "Trip00005.jpg")
        rename.formatPosition = .before
        XCTAssertEqual(rename.newName(for: "a.jpg", index: 1), "00006Trip.jpg")
        rename.format = .date
        rename.formatPosition = .after
        let text = BatchRename.dateText(date)
        XCTAssertEqual(rename.newName(for: "a.jpg", index: 0, date: date), "Trip " + text + ".jpg")
    }

    func testRegularExpressionsAndCase() {
        var rename = BatchRename()
        rename.mode = .regex
        rename.find = #"^(\d{4})-(\d{2})-(\d{2}) (.*)$"#
        rename.replacement = "$4 ($3.$2.$1)"
        XCTAssertEqual(rename.newName(for: "2024-03-01 scan.pdf", index: 0), "scan (01.03.2024).pdf")
        XCTAssertNil(rename.patternProblem)
        rename.find = "(unclosed"
        XCTAssertNotNil(rename.patternProblem)
        XCTAssertEqual(rename.newName(for: "same.pdf", index: 0), "same.pdf", "a bad pattern changes nothing")

        var cased = BatchRename()
        cased.textCase = .title
        XCTAssertEqual(cased.newName(for: "lid study notes.TXT", index: 0), "Lid Study Notes.TXT")
        cased.textCase = .upper
        XCTAssertEqual(cased.newName(for: "lid.txt", index: 0), "LID.txt")
        cased.textCase = .lower
        XCTAssertEqual(cased.newName(for: "LID.txt", index: 0), "lid.txt")
    }

    func testPreviewRefusesClashesAndEmptyNames() {
        var rename = BatchRename()
        rename.mode = .format
        rename.customFormat = "Trip"
        let items = urls(["a.jpg", "b.jpg", "c.png"])
        let rows = rename.preview(items, date: date) { _ in ["a.jpg", "b.jpg", "c.png", "Trip3.png"] }
        XCTAssertEqual(rows.map(\.new), ["Trip1.jpg", "Trip2.jpg", "Trip3.png"])
        XCTAssertEqual(rows.map { $0.problem == nil }, [true, true, false], "Trip3.png is already there")
        XCTAssertFalse(BatchRename.canApply(rows))

        var replace = BatchRename()
        replace.find = "a"
        replace.replacement = "b"
        let swapped = replace.preview(urls(["a.txt", "b.txt"]), date: date) { _ in ["a.txt", "b.txt"] }
        XCTAssertEqual(swapped.map(\.new), ["b.txt", "b.txt"])
        XCTAssertEqual(swapped.map(\.problem), ["Another item gets this name.", "Another item gets this name."])

        var erase = BatchRename()
        erase.find = "notes"
        let empty = erase.preview(urls(["notes"]), date: date) { _ in ["notes"] }
        XCTAssertEqual(empty.first?.problem, "The name is empty.")

        var slash = BatchRename()
        slash.mode = .add
        slash.addText = "/x"
        XCTAssertNotNil(slash.preview(urls(["a.txt"]), date: date) { _ in [] }.first?.problem)
    }

    func testNamesLeavingTheFolderCanBeTaken() {
        var rename = BatchRename()
        rename.mode = .regex
        rename.find = #"^(\w)(\w)$"#
        rename.replacement = "$2$1"
        let rows = rename.preview(urls(["ab", "ba"]), date: date) { _ in ["ab", "ba"] }
        XCTAssertEqual(rows.map(\.new), ["ba", "ab"])
        XCTAssertTrue(BatchRename.canApply(rows), "a swap is fine: each name is freed by the other")
        let unchanged = BatchRename().preview(urls(["ab"]), date: date) { _ in ["ab"] }
        XCTAssertFalse(BatchRename.canApply(unchanged), "nothing to do")
    }

    /// The preview's names go to FileKit as one undoable rename.
    func testAppliedWithFileKitAndUndoneAtOnce() async throws {
        let temp = try TempFolder()
        defer { temp.remove() }
        let files = try ["IMG_1.jpg", "IMG_2.jpg"].map { try temp.file("Trip/" + $0) }
        let trash = try temp.folder("Trash")
        let operations = FileOperations(trash: { url in
            let destination = trash.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })
        var rename = BatchRename()
        rename.find = "IMG_"
        rename.replacement = "Trip "
        let rows = rename.preview(files, date: date) { folder in
            Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        }
        XCTAssertTrue(BatchRename.canApply(rows))
        try await operations.renameItems(rows.map { (item: $0.item, name: $0.new) })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temp.url("Trip").path).sorted(), ["Trip 1.jpg", "Trip 2.jpg"])
        try await operations.undo()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temp.url("Trip").path).sorted(), ["IMG_1.jpg", "IMG_2.jpg"])
    }
}
