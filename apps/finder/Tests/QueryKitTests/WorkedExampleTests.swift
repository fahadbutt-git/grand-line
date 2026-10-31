import XCTest
@testable import QueryKit

final class WorkedExampleTests: XCTestCase {
    private let researchPath = "/Users/me/Library/CloudStorage/GoogleDrive-x/My Drive/01 Research/_Active/Endo/review.docx"

    func testResearchDocuments() {
        let text = "(glauc OR cornea) kind:doc,pdf in:\"01 Research\" modified:<30d -draft"
        let parsed = QueryParser.parse(text)
        XCTAssertTrue(parsed.issues.isEmpty)
        XCTAssertEqual(
            QueryChips.describe(parsed),
            ["glauc or cornea", "Word or PDF", "in 01 Research", "changed in the last 30 days", "not draft"]
        )

        let file: [String: Any] = [
            Key.name: "Glaucoma review.docx",
            Key.content: "Outcomes after intravitreal injection",
            Key.types: "org.openxmlformats.wordprocessingml.document",
            Key.modified: Fixture.date(2026, 10, 20),
        ]
        XCTAssertTrue(matches(text, file, path: researchPath))
        XCTAssertFalse(matches(text, file, path: "/Users/me/Downloads/review.docx"))

        var draft = file
        draft[Key.name] = "Glaucoma review DRAFT.docx"
        XCTAssertFalse(matches(text, draft, path: researchPath))

        var stale = file
        stale[Key.modified] = Fixture.date(2026, 8, 1)
        XCTAssertFalse(matches(text, stale, path: researchPath))

        var spreadsheet = file
        spreadsheet[Key.types] = "org.openxmlformats.spreadsheetml.sheet"
        XCTAssertFalse(matches(text, spreadsheet, path: researchPath))
    }

    func testTriNetXExports() {
        let text = "kind:sheet from:trinetx.com created:2026"
        XCTAssertEqual(chips(text), ["spreadsheet", "from trinetx.com", "created in 2026"])
        let export: [String: Any] = [
            Key.name: "Outcomes.csv",
            Key.types: "public.comma-separated-values-text",
            Key.whereFroms: "https://live.trinetx.com/export/123",
            Key.created: Fixture.date(2026, 3, 2),
        ]
        XCTAssertTrue(matches(text, export))
        var older = export
        older[Key.created] = Fixture.date(2025, 12, 30)
        XCTAssertFalse(matches(text, older))
    }

    func testShortPapersMentioningAPhrase() {
        let text = "text:\"anterior chamber\" kind:pdf pages:<15 sort:modified"
        let query = Fixture.compile(text)
        XCTAssertEqual(query.sort, .modified)
        XCTAssertEqual(chips(text), ["text has \"anterior chamber\"", "PDF", "fewer than 15 pages", "sorted by date modified"])
        let paper: [String: Any] = [
            Key.name: "Case report.pdf",
            Key.content: "Cells in the anterior chamber were graded 2+",
            Key.types: "com.adobe.pdf",
            Key.pages: 9,
        ]
        XCTAssertTrue(query.predicate.evaluate(with: paper))
        var long = paper
        long[Key.pages] = 40
        XCTAssertFalse(query.predicate.evaluate(with: long))
    }

    func testLargeRecentDownloadedImages() {
        let text = "kind:image in:Downloads size:>5mb opened:<7d"
        XCTAssertEqual(chips(text), ["image", "in Downloads", "larger than 5 MB", "opened in the last 7 days"])
        let photo: [String: Any] = [
            Key.name: "IMG_2041.heic",
            Key.types: "public.image",
            Key.size: 8_000_000,
            Key.opened: Fixture.date(2026, 10, 29),
        ]
        XCTAssertTrue(matches(text, photo, path: "/Users/me/Downloads/IMG_2041.heic"))
        XCTAssertFalse(matches(text, photo, path: "/Users/me/Pictures/IMG_2041.heic"))
        var small = photo
        small[Key.size] = 900_000
        XCTAssertFalse(matches(text, small, path: "/Users/me/Downloads/IMG_2041.heic"))
    }
}

final class SavedSearchTests: XCTestCase {
    func testExpansion() {
        let saved: (String) -> String? = { $0 == "ophtho" ? "glaucoma OR retina" : nil }
        XCTAssertTrue(matches("@ophtho kind:pdf", [Key.name: "Retina atlas.pdf", Key.content: "", Key.types: "com.adobe.pdf"], saved: saved))
        XCTAssertFalse(matches("@ophtho kind:pdf", [Key.name: "Cornea.pdf", Key.content: "", Key.types: "com.adobe.pdf"], saved: saved))
    }

    func testUnknownSavedSearchIsIgnored() {
        XCTAssertTrue(matches("@missing cornea", [Key.name: "cornea.pdf", Key.content: ""]))
    }

    func testCyclesStop() {
        let saved: (String) -> String? = { name in
            switch name {
            case "a": return "@b alpha"
            case "b": return "@a beta"
            default: return nil
            }
        }
        XCTAssertTrue(matches("@a", [Key.name: "alpha beta", Key.content: ""], saved: saved))
        XCTAssertFalse(matches("@a", [Key.name: "alpha", Key.content: ""], saved: saved))
    }

    func testSavedSortAndFoldersCarryOver() {
        let saved: (String) -> String? = { name in
            switch name {
            case "recent": return "kind:pdf sort:modified"
            case "inbox": return "in:Downloads"
            default: return nil
            }
        }
        XCTAssertEqual(Fixture.compile("@recent", saved: saved).sort, .modified)
        XCTAssertEqual(Fixture.compile("@recent sort:name", saved: saved).sort, .name)
        let inbox = Fixture.compile("@inbox kind:pdf", saved: saved)
        XCTAssertTrue(inbox.postFilter("/Users/me/Downloads/a.pdf"))
        XCTAssertFalse(inbox.postFilter("/Users/me/Desktop/a.pdf"))
    }
}
