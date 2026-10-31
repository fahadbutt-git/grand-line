import XCTest
@testable import QueryKit

final class IssueTests: XCTestCase {
    private func only(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> QueryIssue? {
        let found = issues(text)
        XCTAssertEqual(found.count, 1, "\(found)", file: file, line: line)
        return found.first
    }

    func testUnknownFilterKeyIsDroppedAndUnderlined() {
        let parsed = QueryParser.parse("knd:pdf cornea")
        XCTAssertEqual(parsed.root, word("cornea"))
        XCTAssertEqual(parsed.issues.map(\.kind), [.unknownFilter])
        XCTAssertEqual(parsed.issues.first?.range, 0..<3)
    }

    func testBadDateKeepsTheRestOfTheQuery() {
        let parsed = QueryParser.parse("kind:pdf modified:soon cornea")
        XCTAssertEqual(parsed.root, Node.and([.term(.kind(.pdf)), word("cornea")]))
        XCTAssertEqual(parsed.issues.map(\.kind), [.badDate])
        XCTAssertEqual(parsed.issues.first?.range, 18..<22)
        XCTAssertTrue(matches("kind:pdf modified:soon cornea", [Key.types: "com.adobe.pdf", Key.name: "cornea.pdf", Key.content: ""]))
    }

    func testBadSize() {
        XCTAssertEqual(only("size:>5zb")?.kind, .badSize)
        XCTAssertEqual(only("size:>5zb")?.range, 5..<9)
    }

    func testBadValues() {
        let kind = QueryParser.parse("kind:pdf,banana")
        XCTAssertEqual(kind.root, Node.term(.kind(.pdf)))
        XCTAssertEqual(kind.issues.map(\.kind), [.badValue])
        XCTAssertEqual(kind.issues.first?.range, 9..<15)
        XCTAssertEqual(only("pages:many")?.range, 6..<10)
        XCTAssertEqual(only("sort:date")?.range, 5..<9)
        XCTAssertEqual(only("name:")?.kind, .badValue)
    }

    func testUnclosedBracket() {
        let parsed = QueryParser.parse("(a b")
        XCTAssertEqual(parsed.root, Node.and([word("a"), word("b")]))
        XCTAssertEqual(parsed.issues.map(\.kind), [.unbalancedBracket])
        XCTAssertEqual(parsed.issues.first?.range, 0..<1)
        XCTAssertEqual(only("((a)")?.range, 0..<1)
    }

    func testStrayClosingBracket() {
        let parsed = QueryParser.parse("a ) b")
        XCTAssertEqual(parsed.root, Node.and([word("a"), word("b")]))
        XCTAssertEqual(parsed.issues.map(\.kind), [.unbalancedBracket])
        XCTAssertEqual(parsed.issues.first?.range, 2..<3)
    }

    func testEmptyGroup() {
        let parsed = QueryParser.parse("a ()")
        XCTAssertEqual(parsed.root, word("a"))
        XCTAssertEqual(parsed.issues.map(\.kind), [.emptyGroup])
        XCTAssertEqual(parsed.issues.first?.range, 2..<4)
    }

    func testDanglingOperators() {
        XCTAssertEqual(root("a OR"), word("a"))
        XCTAssertEqual(only("a OR")?.range, 2..<4)
        XCTAssertEqual(only("OR a")?.range, 0..<2)
        XCTAssertEqual(only("a OR OR b")?.range, 2..<4)
        XCTAssertEqual(root("a OR OR b"), Node.or([word("a"), word("b")]))
        XCTAssertEqual(only("a NOT")?.range, 2..<5)
        XCTAssertEqual(only("a -")?.range, 2..<3)
        XCTAssertEqual(only("(a |)")?.kind, .danglingOperator)
    }

    func testUnclosedQuote() {
        let parsed = QueryParser.parse("\"anterior chamber")
        XCTAssertEqual(parsed.root, Node.term(.text(.phrase("anterior chamber"))))
        XCTAssertEqual(parsed.issues.map(\.kind), [.unclosedQuote])
        XCTAssertEqual(parsed.issues.first?.range, 0..<17)
    }

    func testFolderMixedIntoOr() {
        XCTAssertEqual(only("in:Downloads OR foo")?.kind, .misplacedFolder)
        XCTAssertEqual(only("in:Downloads OR foo")?.range, 0..<19)
        XCTAssertTrue(issues("(in:Downloads OR in:Desktop) -in:Archive (in:Inbox kind:pdf)").isEmpty)
    }

    func testRangeConvertsToUTF16() {
        let text = "\u{1F4C1} knd:x"
        let issue = QueryParser.parse(text).issues.first
        XCTAssertEqual(issue?.range, 2..<5)
        XCTAssertEqual(issue?.nsRange(in: text), NSRange(location: 3, length: 3))
    }
}
