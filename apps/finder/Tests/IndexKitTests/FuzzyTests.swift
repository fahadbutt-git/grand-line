import XCTest
@testable import IndexKit

final class FuzzyTests: XCTestCase {
    func testInitialsAcrossWords() async {
        let index = Fixture.index(["Research/Glaucoma Review Notes.docx", "Research/Glossary.txt"])
        let results = await index.search("glau rn")
        XCTAssertEqual(names(results), ["Glaucoma Review Notes.docx"])
        XCTAssertEqual(results.first?.tier, .fuzzy)
        XCTAssertEqual(results.first?.highlights, [0..<4, 9..<10, 16..<17])
    }

    func testWithoutSpaces() async {
        let index = Fixture.index(["Glaucoma Review Notes.docx"])
        let results = await index.search("glaurn")
        XCTAssertEqual(results.first?.highlights, [0..<4, 9..<10, 16..<17])
    }

    func testFirstLetterMustStartAWord() {
        XCTAssertNil(tier("lrn", "Glaucoma Review Notes"))
        XCTAssertEqual(tier("grn", "Glaucoma Review Notes"), .fuzzy)
    }

    func testLettersMustBeInOrder() {
        XCTAssertNil(tier("nr", "Review Notes"))
    }

    func testRanksBelowSubstring() async {
        let index = Fixture.index(["Review Notes.txt", "xrnx.txt"])
        let results = await index.search("rn")
        XCTAssertEqual(names(results), ["xrnx.txt", "Review Notes.txt"])
    }

    func testMoreWordStartsRankHigher() async {
        let index = Fixture.index(["Rain.txt", "Review Notes.txt"])
        let results = await index.search("rn")
        XCTAssertEqual(names(results), ["Review Notes.txt", "Rain.txt"])
        XCTAssertGreaterThan(rank("rn", "Review Notes.txt")!.quality, rank("rn", "Rain.txt")!.quality)
    }

    func testBetterWordsLiftAFuzzyQuery() {
        // "glau" is a prefix here, and only a scattered match in the other name.
        let strong = rank("glau rn", "Glaucoma Review Notes")!
        let weak = rank("glau rn", "Gate_list-audit_unit report notes")!
        XCTAssertEqual(strong.tier, .fuzzy)
        XCTAssertEqual(weak.tier, .fuzzy)
        XCTAssertEqual(strong.quality, 104)
        XCTAssertEqual(weak.quality, 21)
    }

    func testCamelCaseInitials() {
        XCTAssertEqual(tier("fvc", "FolderViewController.swift"), .fuzzy)
        XCTAssertEqual(rank("fvc", "FolderViewController.swift")?.quality, 12)
    }
}
