import XCTest
@testable import LauncherKit

final class RouterTests: XCTestCase {
    let router = PrefixRouter(pathExists: { ["/Users", "/Applications"].contains($0) }, clipboardHistory: { true })
    let noMaccy = PrefixRouter(pathExists: { _ in false }, clipboardHistory: { false })

    func testNoPrefixSearchesEverything() {
        let q = router.parse("safari")
        XCTAssertNil(q.prefix)
        XCTAssertEqual(q.term, "safari")
        XCTAssertFalse(q.isPath)
    }

    func testEveryPrefix() {
        let cases: [(String, Prefix)] = [
            (". glauc kind:pdf", .files), ("=2+2", .calculator), ("?pm cornea", .web), ("%github", .bookmarks),
            ("<safari", .windows), ("!safari", .windows), ("> ls -la", .shell), (";date", .snippets),
            ("$", .clipboard), (":alpha", .clipboardHistory), ("::alpha", .symbols), ("/", .providers),
            ("/glauc", .files), (",wifi", .settings), ("'cornea", .exact), ("@weekly", .saved),
        ]
        for (text, prefix) in cases {
            XCTAssertEqual(router.parse(text).prefix, prefix, text)
        }
        XCTAssertEqual(router.parse(". glauc kind:pdf").term, "glauc kind:pdf")
        XCTAssertEqual(router.parse("?pm cornea").term, "pm cornea")
    }

    func testSlashListsPrefixesAloneSearchesFilesAndPathsArePaths() {
        XCTAssertEqual(router.parse("/").prefix, .providers)
        XCTAssertEqual(router.parse("/calc").prefix, .files)
        XCTAssertEqual(router.parse("/calc").term, "calc")
        XCTAssertEqual(router.parse("/ ").prefix, .files, "Return on the Files prefix types \"/ \"")
        XCTAssertEqual(router.parse("/ ").term, "")
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

    func testOldPrefixesKeepWorking() {
        XCTAssertEqual(router.parse(". glauc").prefix, .files)
        XCTAssertEqual(router.parse("<safari").prefix, .windows)
        XCTAssertEqual(router.parse("$").prefix, .clipboard)
        // Without Maccy's store, ":" is the symbols, as before.
        XCTAssertEqual(noMaccy.parse(":alpha").prefix, .symbols)
        XCTAssertEqual(noMaccy.parse(":alpha").term, "alpha")
        XCTAssertEqual(router.parse("::alpha").term, "alpha")
    }

    func testCommaBeforeANumberIsNotSettings() {
        XCTAssertNil(router.parse(",5").prefix)
        XCTAssertEqual(router.parse(", dark mode").term, "dark mode")
    }

    func testPrefixesShowTheirFirstTrigger() {
        XCTAssertEqual(Prefix.files.display, "/")
        XCTAssertEqual(Prefix.files.completion, "/ ")
        XCTAssertEqual(Prefix.windows.display, "!")
        XCTAssertEqual(Prefix.symbols.display, "::")
        XCTAssertEqual(Prefix.calculator.chip, "Maths")
        XCTAssertEqual(Prefix.clipboardHistory.chip, "Clipboard")
        XCTAssertEqual(Prefix.shell.chip, "Commands")
        XCTAssertEqual(Prefix.settings.chip, "Settings")
        // Every trigger leads back to its prefix.
        for prefix in Prefix.allCases where prefix != .providers {
            for trigger in prefix.triggers where trigger != ":" {
                XCTAssertEqual(router.parse(trigger + "x").prefix, prefix, trigger)
            }
        }
    }
}
