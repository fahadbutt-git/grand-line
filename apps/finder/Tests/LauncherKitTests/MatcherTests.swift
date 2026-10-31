import XCTest
import IndexKit
@testable import LauncherKit

final class MatcherTests: XCTestCase {
    func tier(_ query: String, _ title: String, exactOnly: Bool = false, strips: Bool = false) -> MatchTier? {
        TextMatcher(query, exactOnly: exactOnly).match(FoldedText(title, stripsExtension: strips))?.tier
    }

    func testTiers() {
        XCTAssertEqual(tier("safari", "Safari"), .exact)
        XCTAssertEqual(tier("saf", "Safari"), .prefix)
        XCTAssertEqual(tier("studio", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(tier("udio", "Visual Studio Code"), .substring)
        XCTAssertEqual(tier("vsc", "Visual Studio Code"), .fuzzy)
        XCTAssertNil(tier("xyz", "Safari"))
    }

    func testExtensionlessNameIsExact() {
        XCTAssertEqual(tier("report", "Report.docx", strips: true), .exact)
        XCTAssertEqual(tier("report", "Report.docx"), .prefix)
    }

    func testCamelCaseAndDigitsStartWords() {
        XCTAssertEqual(tier("drive", "GoogleDrive"), .wordStart)
        XCTAssertEqual(tier("2", "Draft2"), .wordStart)
    }

    func testAccentsAndCaseFold() {
        XCTAssertEqual(tier("cafe", "Café Menu"), .prefix)
        XCTAssertEqual(tier("CAFÉ", "cafe menu"), .prefix)
    }

    func testEveryWordMustMatch() {
        XCTAssertNotNil(tier("gl rev", "Glaucoma Review"))
        XCTAssertNil(tier("gl xyz", "Glaucoma Review"))
    }

    func testExactOnlyRejectsFuzzy() {
        XCTAssertNil(tier("vsc", "Visual Studio Code", exactOnly: true))
        XCTAssertEqual(tier("studio", "Visual Studio Code", exactOnly: true), .wordStart)
    }

    func testHighlightsAreUTF16RangesOfTheOriginal() {
        let title = FoldedText("Écran Report")
        let matcher = TextMatcher("rep")
        let hit = matcher.match(title)!
        XCTAssertEqual(matcher.highlights(hit, in: title), [6..<9])
        let emoji = FoldedText("🙂 Notes")
        let m2 = TextMatcher("notes")
        XCTAssertEqual(m2.highlights(m2.match(emoji)!, in: emoji), [3..<8])
    }
}
