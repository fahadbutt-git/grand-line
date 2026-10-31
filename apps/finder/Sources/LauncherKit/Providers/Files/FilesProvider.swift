import Foundation
import IndexKit
import QueryKit

/// How a `.` query is searched: plain words go to the name index and to
/// Spotlight's text search; anything with filters (kind:, in:, modified:…) goes
/// to Spotlight only, compiled by QueryKit in the app.
public struct FileQueryPlan: Sendable, Equatable {
    /// Words for the name index, or nil when the query has filters.
    public let names: String?
    /// The QueryKit text for Spotlight, or nil when Spotlight is not needed.
    public let spotlight: String?
    /// Problems to underline in the field.
    public let issues: [String]

    public static func make(_ text: String, content: Bool) -> FileQueryPlan {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return FileQueryPlan(names: nil, spotlight: nil, issues: []) }
        let parsed = QueryParser.parse(trimmed)
        let issues = parsed.issues.map(\.message)
        if let words = plainWords(parsed.root), parsed.sort == nil {
            return FileQueryPlan(names: words.joined(separator: " "), spotlight: content ? trimmed : nil, issues: issues)
        }
        return FileQueryPlan(names: nil, spotlight: trimmed, issues: issues)
    }

    /// The words of a query that is only words and prefixes ANDed together.
    static func plainWords(_ node: Node?) -> [String]? {
        guard let node else { return nil }
        switch node {
        case .term(.text(let pattern)) where pattern.style != .phrase:
            return [pattern.text]
        case .and(let nodes):
            var words: [String] = []
            for child in nodes {
                guard let more = plainWords(child) else { return nil }
                words += more
            }
            return words
        default:
            return nil
        }
    }
}

/// Files: the name index as you type (in every search), and with the `.` prefix
/// also Spotlight's content and metadata search through QueryKit.
public struct FilesProvider: LaunchProvider {
    public let id = "files"
    public let title = "Files"
    public let symbol = "doc.text.magnifyingglass"
    public let prefix: Prefix? = .files
    public let inGlobalSearch = true
    let paths: GrandLinePaths
    let names: @Sendable (String, Int) async -> [IndexMatch]
    let spotlight: @Sendable (String, Int) async -> [FileHit]
    let unreadable: @Sendable () async -> [String]

    /// - Parameters:
    ///   - names: the name index search (FileIndex.search).
    ///   - spotlight: runs a QueryKit query with NSMetadataQuery.
    ///   - unreadable: folders the name index was not allowed to read.
    public init(
        paths: GrandLinePaths = GrandLinePaths(),
        names: @escaping @Sendable (String, Int) async -> [IndexMatch],
        spotlight: @escaping @Sendable (String, Int) async -> [FileHit],
        unreadable: @escaping @Sendable () async -> [String] = { [] }
    ) {
        self.paths = paths
        self.names = names
        self.spotlight = spotlight
        self.unreadable = unreadable
    }

    public func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        let own = query.prefix == .files
        let plan = FileQueryPlan.make(query.term, content: own)
        var hits: [FileHit] = []
        if let words = plan.names {
            hits = await names(words, own ? 40 : 12).map { FileHit($0) }
        }
        try Task.checkCancellation()
        if let text = plan.spotlight {
            var seen = Set(hits.map(\.path))
            for hit in await spotlight(text, 60) where seen.insert(hit.path).inserted { hits.append(hit) }
        }
        try Task.checkCancellation()
        // Apps have their own provider; outside `.` they would show twice.
        if !own { hits.removeAll { $0.ext == "app" } }
        let now = Date()
        let rows = hits.map { FileResults.result($0, paths: paths, now: now) }
        guard plan.names != nil || plan.spotlight != nil else { return rows }
        return rows + FileResults.permissionRows(await unreadable(), home: paths.home)
    }
}
