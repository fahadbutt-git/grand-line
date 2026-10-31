import Foundation
@testable import QueryKit

enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static let home = "/Users/me"
    static let now = date(2026, 10, 31, 12)

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func compile(_ text: String, saved: (String) -> String? = { _ in nil }) -> SpotlightQuery {
        SpotlightCompiler.compile(QueryParser.parse(text), now: now, calendar: calendar, home: home, savedSearch: saved)
    }
}

enum Key {
    static let name = "kMDItemFSName"
    static let content = "kMDItemTextContent"
    static let types = "kMDItemContentTypeTree"
    static let modified = "kMDItemContentModificationDate"
    static let created = "kMDItemContentCreationDate"
    static let opened = "kMDItemLastUsedDate"
    static let size = "kMDItemFSSize"
    static let pages = "kMDItemNumberOfPages"
    static let whereFroms = "kMDItemWhereFroms"
    static let tags = "kMDItemUserTags"
    static let authors = "kMDItemAuthors"
}

/// Multi-valued Spotlight attributes are given as a single string, since Spotlight
/// compares each element while plain NSPredicate evaluation compares the whole value.
func matches(
    _ text: String,
    _ attributes: [String: Any],
    path: String = "/Users/me/Documents/file",
    saved: (String) -> String? = { _ in nil }
) -> Bool {
    let query = Fixture.compile(text, saved: saved)
    return query.predicate.evaluate(with: attributes) && query.postFilter(path)
}

func root(_ text: String) -> Node? {
    QueryParser.parse(text).root
}

func issues(_ text: String) -> [QueryIssue] {
    QueryParser.parse(text).issues
}

func chips(_ text: String) -> [String] {
    QueryChips.describe(QueryParser.parse(text))
}

func word(_ text: String) -> Node {
    .term(.text(.word(text)))
}
