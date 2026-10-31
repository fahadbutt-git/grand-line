import XCTest
@testable import LauncherKit

final class RouterTests: XCTestCase {
    let router = PrefixRouter(pathExists: { ["/Users", "/Applications"].contains($0) })

    func testNoPrefixSearchesEverything() {
        let q = router.parse("safari")
        XCTAssertNil(q.prefix)
        XCTAssertEqual(q.term, "safari")
        XCTAssertFalse(q.isPath)
    }

    func testEveryPrefix() {
        let cases: [(String, Prefix)] = [
            (". glauc kind:pdf", .files), ("=2+2", .calculator), ("?pm cornea", .web), ("%github", .bookmarks),
            ("<safari", .windows), ("!call Smith 20m", .reminder), ("> ls -la", .shell), (";date", .snippets),
            ("$", .clipboard), (":alpha", .symbols), ("/", .providers), ("'cornea", .exact), ("@weekly", .saved),
        ]
        for (text, prefix) in cases {
            XCTAssertEqual(router.parse(text).prefix, prefix, text)
        }
        XCTAssertEqual(router.parse(". glauc kind:pdf").term, "glauc kind:pdf")
        XCTAssertEqual(router.parse("?pm cornea").term, "pm cornea")
    }

    func testSlashListsPrefixesButPathsArePaths() {
        XCTAssertEqual(router.parse("/calc").prefix, .providers)
        XCTAssertEqual(router.parse("/calc").term, "calc")
        XCTAssertTrue(router.parse("/Users").isPath)
        XCTAssertTrue(router.parse("/opt/homebrew").isPath)
        XCTAssertTrue(router.parse("~/Drive").isPath)
        XCTAssertTrue(router.parse("~").isPath)
    }

    func testNumbersAreSumsNotPrefixes() {
        XCTAssertNil(router.parse(".5 * 2").prefix)
        XCTAssertNil(router.parse("$40 in usd").prefix)
        XCTAssertEqual(router.parse("$ maccy").prefix, .clipboard)
    }

    func testKeywordSplit() {
        let q = router.parse("pm  corneal edema")
        XCTAssertEqual(q.keywordSplit?.keyword, "pm")
        XCTAssertEqual(q.keywordSplit?.rest, "corneal edema")
        XCTAssertNil(router.parse("pm").keywordSplit)
    }

    func testUsageKeyIncludesPrefixAndFolds() {
        XCTAssertEqual(router.parse("Café").usageKey, "cafe")
        XCTAssertEqual(router.parse(";Date").usageKey, ";date")
    }
}
