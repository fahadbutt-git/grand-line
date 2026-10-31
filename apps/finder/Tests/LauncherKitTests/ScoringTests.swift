import XCTest
import IndexKit
@testable import LauncherKit

/// fzf-style scoring inside the tiers, and the letter-mask prefilter.
final class ScoringTests: XCTestCase {
    func hit(_ query: String, _ title: String) -> TextMatcher.Hit? {
        TextMatcher(query).match(FoldedText(title))
    }

    func testPrefilterSkipsTextsMissingALetter() {
        XCTAssertFalse(TextMatcher("xyz").mayMatch(FoldedText("Safari")))
        XCTAssertTrue(TextMatcher("saf").mayMatch(FoldedText("Safari")))
        XCTAssertTrue(TextMatcher("vs code").mayMatch(FoldedText("Visual Studio Code")), "spaces are not letters to find")
        XCTAssertFalse(TextMatcher("vs codex").mayMatch(FoldedText("Visual Studio Code")))
        XCTAssertNil(hit("q", "Safari"))
    }

    func testWordBoundaryBeatsInsideAWord() throws {
        // Both are substrings of their titles; the one at a word start scores higher.
        let start = try XCTUnwrap(hit("view", "Glaucoma view"))
        let inside = try XCTUnwrap(hit("view", "Glaucomaview"))
        XCTAssertEqual(start.tier, .wordStart)
        XCTAssertEqual(inside.tier, .substring)
        XCTAssertGreaterThan(start.quality, inside.quality)
    }

    func testCamelCaseHumpScoresAsAWordStart() throws {
        let camel = try XCTUnwrap(hit("gd", "GoogleDrive"))
        let plain = try XCTUnwrap(hit("gd", "Goodwill"))
        XCTAssertEqual(camel.tier, .fuzzy)
        XCTAssertEqual(plain.tier, .fuzzy)
        XCTAssertGreaterThan(camel.quality, plain.quality)
    }

    func testConsecutiveLettersBeatScatteredWordStarts() throws {
        let runs = try XCTUnwrap(hit("glre", "Glaucoma Review"))
        let scattered = try XCTUnwrap(hit("glre", "Gold Lake Ridge Estate"))
        XCTAssertGreaterThan(runs.quality, scattered.quality)
    }

    func testLongerGapsCostMore() throws {
        let near = try XCTUnwrap(hit("ac", "abc"))
        let far = try XCTUnwrap(hit("ac", "abbbc"))
        XCTAssertGreaterThan(near.quality, far.quality)
    }

    func testFuzzyPlacesLettersWhereTheScoreIsHighest() throws {
        let text = FoldedText("Go cxr Car Ride")
        let word = Array("gcr".utf8)
        let best = try XCTUnwrap(FuzzyScore.best(word, in: text))
        let greedy = try XCTUnwrap(FuzzyScore.greedy(word, in: text))
        XCTAssertGreaterThan(best.score, greedy.score)
        XCTAssertEqual(best.score, FuzzyScore.score(best.positions, in: text))
        XCTAssertEqual(best.positions.first, 0)
    }

    func testFuzzyHighlightsTheChosenLetters() throws {
        let title = FoldedText("Visual Studio Code")
        let matcher = TextMatcher("vsc")
        let found = try XCTUnwrap(matcher.match(title))
        XCTAssertEqual(found.tier, .fuzzy)
        XCTAssertEqual(matcher.highlights(found, in: title), [0..<1, 7..<8, 14..<15])
    }

    func testFirstLetterMustStartAWord() {
        XCTAssertNil(hit("ai", "Safari"), "a fuzzy match starts at a word start, as before")
    }

    func testTiersStillComeBeforeScore() {
        let rows = [
            Make.row("Clear Old Data Entries"),
            Make.row("Codex Notes"),
            Make.row("Code"),
            Make.row("Barcode"),
        ]
        let query = LaunchQuery(raw: "code")
        let ranked = Ranker().rank(Make.matched(rows, "code"), query: query).map(\.title)
        XCTAssertEqual(ranked, ["Code", "Codex Notes", "Barcode", "Clear Old Data Entries"])
    }

    func testFrecencyBlendsWithinATierButNotAcrossOne() {
        func key(_ title: Int, quality: Int, frecency: Double) -> RankKey {
            RankKey(fallback: false, alias: .none, title: title, keyword: 5, frecency: frecency, quality: quality)
        }
        let fuzzy = MatchTier.fuzzy.rawValue, prefix = MatchTier.prefix.rawValue
        // A habit lifts a row over a slightly better match…
        XCTAssertLessThan(key(fuzzy, quality: 60, frecency: 4), key(fuzzy, quality: 62, frecency: 0))
        // …not over a much better one…
        XCTAssertLessThan(key(fuzzy, quality: 140, frecency: 0), key(fuzzy, quality: 60, frecency: 4))
        // …and never over a better tier.
        XCTAssertLessThan(key(prefix, quality: 20, frecency: 0), key(fuzzy, quality: 500, frecency: 1_000))
    }

    func testFilesFromTheIndexAreScoredByTheSameMatcher() async throws {
        let provider = FilesProvider(
            paths: GrandLinePaths(home: "/Users/me"),
            names: { _, _ in [
                IndexMatch(path: "/Users/me/glaucomaview.txt", name: "glaucomaview.txt", isFolder: false, tier: .substring, highlights: []),
                IndexMatch(path: "/Users/me/glaucoma view.txt", name: "glaucoma view.txt", isFolder: false, tier: .wordStart, highlights: []),
            ] },
            spotlight: { _, _ in [] }
        )
        let rows = try await provider.results(for: LaunchQuery(raw: "view"))
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.match.quality > 0 })
    }
}
