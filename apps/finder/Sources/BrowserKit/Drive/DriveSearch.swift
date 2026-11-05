import Foundation

/// Talks to the Drive API with the account's access token: a 401 refreshes the
/// token once, and rate limits (403 with a rate-limit reason, 429) pause every
/// request with a doubling back-off, so a busy day never hammers the API.
public actor DriveClient {
    private let transport: DriveTransport
    private let tokens: DriveTokenSource
    private let now: @Sendable () -> Date
    private var pausedUntil: Date?
    private var backoff: TimeInterval = 0

    public init(transport: DriveTransport, tokens: DriveTokenSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.tokens = tokens
        self.now = now
    }

    /// Up to `DriveAPI.pageSize` files whose contents (or names) hold the terms.
    public func search(_ terms: String) async throws -> [DriveFile] {
        guard let request = DriveAPI.searchRequest(terms: terms) else { return [] }
        return try DriveAPI.parseList(try await send(request)).files
    }

    /// `files.get`: a folder's name and parents, or with fields "id" the id
    /// behind an alias such as "root".
    public func file(_ id: String, fields: String = DriveAPI.folderFields) async throws -> DriveFile {
        guard let request = DriveAPI.fileRequest(id: id, fields: fields) else { throw DriveError.badResponse }
        return try DriveAPI.parseFile(try await send(request))
    }

    /// When requests may go out again, if a rate limit paused them.
    public var pause: Date? {
        guard let pausedUntil, now() < pausedUntil else { return nil }
        return pausedUntil
    }

    func send(_ request: URLRequest) async throws -> Data {
        if let until = pause { throw DriveError.rateLimited(until: until) }
        var token = try await tokens.accessToken(refresh: false)
        for attempt in 0..<2 {
            var signed = request
            signed.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport.send(signed)
            let status = response.statusCode
            if status == 429 || (status == 403 && DriveAPI.isRateLimit(data)) {
                backoff = min(max(backoff * 2, 2), 120)
                let asked = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init) ?? 0
                let until = now().addingTimeInterval(max(backoff, asked))
                pausedUntil = until
                throw DriveError.rateLimited(until: until)
            }
            switch status {
            case 200..<300:
                backoff = 0
                pausedUntil = nil
                return data
            case 401 where attempt == 0:
                token = try await tokens.accessToken(refresh: true)
            case 401:
                throw DriveError.needsReconnect
            default:
                throw DriveError.http(status)
            }
        }
        throw DriveError.needsReconnect
    }
}

/// Where a Drive file sits under My Drive, by walking its parents up to the
/// My Drive folder. Each folder is looked up once per session (`files.get`
/// with name and parents), and lookups already under way are shared.
public actor DrivePathResolver {
    public typealias Lookup = @Sendable (_ id: String, _ fields: String) async throws -> DriveFile

    private struct Folder: Sendable {
        let name: String
        let parent: String?
    }

    private let lookup: Lookup
    private var folders: [String: Folder] = [:]
    private var pending: [String: Task<Folder?, Never>] = [:]
    private var rootID: String?
    private var rootTask: Task<String?, Never>?
    /// Folders looked up so far, for tests and the log.
    public private(set) var lookups = 0

    public init(lookup: @escaping Lookup) {
        self.lookup = lookup
    }

    /// The file's path below My Drive, as Drive for desktop names things on
    /// disk (link files for Docs, Sheets and Slides). Nil for files outside
    /// My Drive (shared with you, other drives) or when a lookup fails.
    public func components(of file: DriveFile) async -> [String]? {
        guard let root = await root() else { return nil }
        var names = [file.localName]
        var parent = file.parents.first
        var depth = 0
        while let id = parent {
            if id == root { return names.reversed() }
            guard depth < 64, let folder = await folder(id) else { return nil }
            names.append(folder.name)
            parent = folder.parent
            depth += 1
        }
        return nil
    }

    private func root() async -> String? {
        if let rootID { return rootID }
        if let rootTask { return await rootTask.value }
        let lookup = self.lookup
        let task = Task<String?, Never> { (try? await lookup("root", "id"))?.id }
        rootTask = task
        let id = await task.value
        rootTask = nil
        if let id { rootID = id }
        return id
    }

    private func folder(_ id: String) async -> Folder? {
        if let known = folders[id] { return known }
        if let task = pending[id] { return await task.value }
        lookups += 1
        let lookup = self.lookup
        let task = Task<Folder?, Never> {
            guard let file = try? await lookup(id, DriveAPI.folderFields) else { return nil }
            return Folder(name: file.localName, parent: file.parents.first)
        }
        pending[id] = task
        let folder = await task.value
        pending[id] = nil
        if let folder { folders[id] = folder }
        return folder
    }

    /// Forgets every folder (a disconnect, another account).
    public func reset() {
        folders = [:]
        rootID = nil
    }
}

/// One file found in Drive, with its streamed path under My Drive when it
/// could be worked out and is there on disk.
public struct DriveHit: Equatable, Sendable, Identifiable {
    public let file: DriveFile
    public let localPath: String?

    public init(file: DriveFile, localPath: String?) {
        self.file = file
        self.localPath = localPath
    }

    public var id: String { file.id }

    /// What a click opens: the streamed file (Drive downloads it as it
    /// opens), else the file's page on the web.
    public var target: DriveOpenTarget? {
        if let localPath { return file.isFolder ? .folder(localPath) : .file(localPath) }
        return file.webViewLink.map(DriveOpenTarget.web)
    }
}

public enum DriveOpenTarget: Equatable, Sendable {
    case file(String)
    case folder(String)
    case web(URL)
}

public enum DriveResults {
    /// The path for `components` in the first account whose My Drive holds
    /// it on disk. Nil when no account does.
    public static func localPath(components: [String], myDrives: [String], exists: (String) -> Bool) -> String? {
        guard !components.isEmpty else { return nil }
        for root in myDrives {
            let path = ([root] + components).joined(separator: "/")
            if exists(path) { return path }
        }
        return nil
    }

    /// Hits not already among the local results, each file once, in Drive's order.
    public static func dedupe(_ hits: [DriveHit], local: Set<String>) -> [DriveHit] {
        let shown = Set(local.map(normalized))
        var seen = Set<String>()
        return hits.filter { hit in
            guard seen.insert(hit.file.id).inserted else { return false }
            guard let path = hit.localPath else { return true }
            return !shown.contains(normalized(path))
        }
    }

    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping
    }

    /// The plain words a Drive search looks for: only a query of words (no
    /// filters, which Drive cannot apply the same way) is sent.
    public static func terms(for plan: SearchPlan) -> String? {
        guard plan.nameText != nil, !plan.isUnconstrained else { return nil }
        let words = plan.words.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.joined(separator: " ")
    }
}

/// A Drive search from start to finish: `files.list`, each file's place under
/// My Drive, and whether it is there on disk.
public struct DriveSearchEngine: Sendable {
    private let client: DriveClient
    private let resolver: DrivePathResolver
    private let myDrives: @Sendable () -> [String]
    private let exists: @Sendable (String) -> Bool

    public init(client: DriveClient, resolver: DrivePathResolver,
                myDrives: @escaping @Sendable () -> [String], exists: @escaping @Sendable (String) -> Bool) {
        self.client = client
        self.resolver = resolver
        self.myDrives = myDrives
        self.exists = exists
    }

    public func search(_ terms: String) async throws -> [DriveHit] {
        let files = try await client.search(terms)
        try Task.checkCancellation()
        let roots = myDrives()
        let resolver = self.resolver
        let exists = self.exists
        let paths = await withTaskGroup(of: (Int, String?).self) { group -> [Int: String] in
            for (index, file) in files.enumerated() {
                group.addTask {
                    guard !roots.isEmpty, let components = await resolver.components(of: file) else { return (index, nil) }
                    return (index, DriveResults.localPath(components: components, myDrives: roots, exists: exists))
                }
            }
            var found: [Int: String] = [:]
            for await (index, path) in group { if let path { found[index] = path } }
            return found
        }
        try Task.checkCancellation()
        return files.enumerated().map { DriveHit(file: $0.element, localPath: paths[$0.offset]) }
    }
}
