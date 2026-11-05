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

    // MARK: Tight matches

    /// Names a search for "conj" once showed by scattered letters (c-o-n from
    /// "config", the j from ".json"). Only real matches remain.
    static let conjNames = [
        "Projects/Conj Flap/",
        "Papers/K1. Conjunctivitis in the First Month of Life.pdf",
        "Studies/Lid Study - CONJ/",
        "Downloads/prisma_config.json",
        "Downloads/BO13. Astigmatic Refractive Correction - Jackson Cross.pdf",
        "Downloads/c2_Early_anterior-chamber_injection_-_matched_30d_v1.0_302141.zip",
        "Downloads/combined_Li_J_et_al_2025.txt",
        "Downloads/completeness_summary.json",
    ]

    func testConjFindsOnlyNamesThatHoldIt() async {
        let index = Fixture.index(Self.conjNames)
        let results = await index.search("conj")
        XCTAssertEqual(Set(names(results)), ["Conj Flap", "K1. Conjunctivitis in the First Month of Life.pdf", "Lid Study - CONJ"])
        XCTAssertEqual(results.first?.name, "Conj Flap")
        XCTAssertFalse(results.contains { $0.tier == .fuzzy })
    }

    func testScatteredLettersAreNotAMatch() {
        XCTAssertNil(tier("conj", "prisma_config.json"), "the extension never gives a letter")
        XCTAssertNil(tier("conj", "BO13. Astigmatic Refractive Correction - Jackson Cross.pdf"), "n is too far into Correction")
        XCTAssertNil(tier("conj", "c2_Early_anterior-chamber_injection_-_matched_30d_v1.0_302141.zip"))
        XCTAssertNil(tier("conj", "combined_Li_J_et_al_2025.txt"), "co and an n further in, then J: not the start of combined")
        XCTAssertNil(tier("conj", "completeness_summary.json"))
        XCTAssertEqual(tier("conj", "Conj Flap"), .prefix)
        XCTAssertEqual(tier("conj", "K1. Conjunctivitis in the First Month of Life.pdf"), .wordStart)
        XCTAssertEqual(tier("conj", "Lid Study - CONJ"), .wordStart)
    }

    func testTightMatchesStillFound() {
        XCTAssertEqual(tier("spf", "System Preferences"), .fuzzy, "two letters skipped inside a word")
        XCTAssertEqual(tier("glre", "Gold Lake Ridge Estate"), .fuzzy)
        XCTAssertEqual(tier("rn", "Rain.txt"), .fuzzy)
        XCTAssertNil(tier("rn", "Rxxxxn.txt"), "four letters skipped inside a word")
        XCTAssertNil(tier("gn", "Glaucoma Review Cases Old Notes"), "three words skipped")
        XCTAssertEqual(tier("gn", "Glaucoma Review Cases Notes"), .fuzzy, "two words skipped")
    }

    func testExtensionNeverTakesPart() async {
        XCTAssertNil(tier("rnx", "Review Notes.xlsx"))
        XCTAssertEqual(tier("rnx", "Review Notes xlsx"), .fuzzy, "a word, not an extension")
        XCTAssertEqual(tier("drl", "Dr. Lee notes"), .fuzzy, "a dot followed by a space starts no extension")
        // A folder has no extension: all of its name counts.
        let index = Fixture.index(["a/Review Notes.xlsx", "b/Review Notes.xlsx/"])
        let results = await index.search("rnx")
        XCTAssertEqual(results.map(\.path), ["/Index/b/Review Notes.xlsx"])
    }
}
