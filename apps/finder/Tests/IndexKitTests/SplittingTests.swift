import XCTest
@testable import IndexKit

/// Where words start inside a name.
final class SplittingTests: XCTestCase {
    func testSeparatorsDigitsAndCamelCase() {
        XCTAssertEqual(wordStarts("data_cornea-graft.v2 finalDraft"), [0, 5, 12, 18, 19, 21, 26])
    }

    func testEverySeparatorStartsAWord() {
        for name in ["data cornea", "data_cornea", "data-cornea", "data.cornea", "dataCornea", "data(cornea)"] {
            XCTAssertEqual(tier("cornea", name), .wordStart, name)
        }
        XCTAssertEqual(tier("cornea", "datacornea"), .substring)
    }

    func testLettersAndDigitsSplit() {
        XCTAssertEqual(tier("2026", "report2026.pdf"), .wordStart)
        XCTAssertEqual(tier("pdf", "v2pdf"), .wordStart)
    }

    func testUppercaseRunsAreOneWord() {
        XCTAssertEqual(wordStarts("PDFReader"), [0])
        XCTAssertEqual(wordStarts("myPDF"), [0, 2])
    }

    func testNonASCIINamesSplitOnSeparators() {
        XCTAssertEqual(tier("etude", "Café Étude.txt"), .wordStart)
        XCTAssertEqual(tier("cafe", "Café Étude.txt"), .prefix)
    }

    func testQueryWordsSplitOnWhitespace() {
        let query = SearchQuery("  Glau \t RN  ")
        XCTAssertEqual(query?.bytes, Array("glau rn".utf8))
        XCTAssertEqual(query?.words, [0..<4, 5..<7])
        XCTAssertNil(SearchQuery(" \n "))
    }

    func testFoldAndMask() {
        XCTAssertEqual(NameFold.fold("ÉtudeFINAL"), Array("etudefinal".utf8))
        XCTAssertEqual(NameFold.mask(Array("ab".utf8)), 0b11)
        XCTAssertEqual(NameFold.mask(Array("a b".utf8)), 0b11)
        let name = NameFold.mask(Array("review notes".utf8))
        let query = NameFold.mask(Array("rn".utf8))
        XCTAssertEqual(name & query, query)
        XCTAssertNotEqual(name & NameFold.mask(Array("z".utf8)), NameFold.mask(Array("z".utf8)))
    }
}
