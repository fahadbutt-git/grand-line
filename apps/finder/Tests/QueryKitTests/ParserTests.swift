import XCTest
@testable import QueryKit

final class ParserTests: XCTestCase {
    func testTermsAreAndedByDefault() {
        XCTAssertEqual(root("glauc cornea"), Node.and([word("glauc"), word("cornea")]))
    }

    func testOrKeywordAndPipe() {
        let expected = Node.or([word("a"), word("b")])
        XCTAssertEqual(root("a OR b"), expected)
        XCTAssertEqual(root("a | b"), expected)
        XCTAssertEqual(root("a|b"), expected)
    }

    func testLowercaseKeywordsOnlyStandingAlone() {
        XCTAssertEqual(root("a or b"), Node.or([word("a"), word("b")]))
        XCTAssertEqual(root("not a"), Node.not(word("a")))
        XCTAssertEqual(root("orange notes"), Node.and([word("orange"), word("notes")]))
    }

    func testAndBindsTighterThanOr() {
        XCTAssertEqual(root("a b OR c"), Node.or([.and([word("a"), word("b")]), word("c")]))
        XCTAssertEqual(root("a OR b c"), Node.or([word("a"), .and([word("b"), word("c")])]))
    }

    func testNotBindsTighterThanAnd() {
        XCTAssertEqual(root("NOT a b"), Node.and([.not(word("a")), word("b")]))
        XCTAssertEqual(root("NOT a OR b"), Node.or([.not(word("a")), word("b")]))
    }

    func testDashNegatesTermsAndGroups() {
        XCTAssertEqual(root("-draft"), Node.not(word("draft")))
        XCTAssertEqual(root("x -(a OR b)"), Node.and([word("x"), .not(.or([word("a"), word("b")]))]))
        XCTAssertEqual(root("-\"old copy\""), Node.not(.term(.text(.phrase("old copy")))))
    }

    func testHyphenInsideWordIsNotNegation() {
        XCTAssertEqual(root("cross-linking"), word("cross-linking"))
    }

    func testNestedGroups() {
        let expected = Node.and([
            .or([word("a"), word("b")]),
            .or([word("c"), .and([word("d"), word("e")])]),
        ])
        XCTAssertEqual(root("((a OR b) (c OR (d e)))"), expected)
    }

    func testGroupedAndIsFlattened() {
        XCTAssertEqual(root("(a b) c"), Node.and([word("a"), word("b"), word("c")]))
    }

    func testStraightQuotePhrase() {
        XCTAssertEqual(root("\"anterior chamber\""), Node.term(.text(.phrase("anterior chamber"))))
    }

    func testCurlyQuotePhrase() {
        XCTAssertEqual(root("\u{201C}anterior chamber\u{201D}"), Node.term(.text(.phrase("anterior chamber"))))
    }

    func testQuotedKeywordIsAPhrase() {
        XCTAssertEqual(root("a \"OR\" b"), Node.and([word("a"), .term(.text(.phrase("OR"))), word("b")]))
    }

    func testPrefix() {
        XCTAssertEqual(root("endo*"), Node.term(.text(.prefix("endo"))))
        XCTAssertEqual(root("name:endo*"), Node.term(.field(.name, .prefix("endo"))))
    }

    func testFilterKeysAndKindsAreCaseInsensitive() {
        XCTAssertEqual(root("KIND:PDF"), Node.term(.kind(.pdf)))
    }

    func testCommaSeparatedValuesMeanAnyOf() {
        XCTAssertEqual(root("kind:doc,pdf"), Node.or([.term(.kind(.doc)), .term(.kind(.pdf))]))
        XCTAssertEqual(
            root("in:\"01 Research\",\"02 Ideas\""),
            Node.or([.term(.folder("01 Research")), .term(.folder("02 Ideas"))])
        )
    }

    func testTextFilterKeys() {
        XCTAssertEqual(root("name:protocol"), Node.term(.field(.name, .word("protocol"))))
        XCTAssertEqual(root("text:\"anterior chamber\""), Node.term(.field(.content, .phrase("anterior chamber"))))
        XCTAssertEqual(root("ext:docx"), Node.term(.field(.ext, .word("docx"))))
        XCTAssertEqual(root("from:trinetx.com"), Node.term(.field(.from, .word("trinetx.com"))))
        XCTAssertEqual(root("tag:Urgent"), Node.term(.field(.tag, .word("Urgent"))))
        XCTAssertEqual(root("author:Smith"), Node.term(.field(.author, .word("Smith"))))
    }

    func testComparisonFilterKeys() {
        XCTAssertEqual(root("modified:<30d"), Node.term(.date(.modified, .less(.daysAgo(30)))))
        XCTAssertEqual(root("created:2026"), Node.term(.date(.created, .equal(.year(2026)))))
        XCTAssertEqual(root("opened:week"), Node.term(.date(.opened, .equal(.daysAgo(7)))))
        XCTAssertEqual(root("size:>5mb"), Node.term(.size(.greater(5_000_000))))
        XCTAssertEqual(root("pages:10..20"), Node.term(.pages(.between(10, 20))))
    }

    func testSortIsExtracted() {
        let parsed = QueryParser.parse("foo sort:size")
        XCTAssertEqual(parsed.root, word("foo"))
        XCTAssertEqual(parsed.sort, .size)
        XCTAssertTrue(parsed.issues.isEmpty)
    }

    func testSavedSearchReference() {
        XCTAssertEqual(root("@weekly kind:pdf"), Node.and([.saved("weekly"), .term(.kind(.pdf))]))
        XCTAssertEqual(root("@\"grant drafts\""), Node.saved("grant drafts"))
    }

    func testAliases() {
        XCTAssertEqual(root("pdf:"), Node.term(.kind(.pdf)))
        XCTAssertEqual(root("pdf:endo"), Node.and([.term(.kind(.pdf)), word("endo")]))
        XCTAssertEqual(root("docx:"), Node.term(.field(.ext, .word("docx"))))
        XCTAssertEqual(root("drive:"), Node.term(.location(.googleDrive)))
        XCTAssertEqual(root("local: budget"), Node.and([.term(.location(.local)), word("budget")]))
        XCTAssertEqual(root("proj:Endo"), Node.term(.folder("Endo")))
    }

    func testEmptyQuery() {
        let parsed = QueryParser.parse("   ")
        XCTAssertNil(parsed.root)
        XCTAssertTrue(parsed.issues.isEmpty)
    }
}
