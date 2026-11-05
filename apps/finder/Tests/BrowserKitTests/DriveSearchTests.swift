import Foundation
import XCTest
@testable import BrowserKit

/// "Found in Google Drive": the Drive API query, its answers, where each file
/// sits under My Drive, and what the local results already show. Every
/// answer comes from `MockTransport`; nothing here touches the network.
final class DriveSearchTests: XCTestCase {
    // MARK: Query escaping

    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(DriveAPI.escape("plain words"), "plain words")
        XCTAssertEqual(DriveAPI.escape("O'Brien"), #"O\'Brien"#)
        XCTAssertEqual(DriveAPI.escape(#"C:\notes"#), #"C:\\notes"#)
        XCTAssertEqual(DriveAPI.escape(#"\'"#), #"\\\'"#, "the backslash is escaped before the quote it precedes")
    }

    func testFullTextQuery() {
        XCTAssertEqual(DriveAPI.fullTextQuery("glaucoma  drops"), "fullText contains 'glaucoma drops' and trashed = false")
        XCTAssertEqual(DriveAPI.fullTextQuery("it's"), #"fullText contains 'it\'s' and trashed = false"#)
        XCTAssertNil(DriveAPI.fullTextQuery("   "))
    }

    func testSearchRequestAsksForTheFieldsAndPageSize() throws {
        let request = try XCTUnwrap(DriveAPI.searchRequest(terms: "a+b & c=d"))
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, "www.googleapis.com")
        XCTAssertEqual(url.path, "/drive/v3/files")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "fullText contains 'a+b & c=d' and trashed = false")
        XCTAssertEqual(items["fields"], "files(id,name,mimeType,modifiedTime,size,parents,webViewLink),nextPageToken")
        XCTAssertEqual(items["pageSize"], "25")
        XCTAssertEqual(items["corpora"], "user")
        XCTAssertFalse(url.absoluteString.contains("+"), "a plus sign is sent encoded, not as a space")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testFileRequestEncodesTheID() throws {
        let url = try XCTUnwrap(DriveAPI.fileRequest(id: "abc/def")?.url)
        XCTAssertEqual(url.absoluteString, "https://www.googleapis.com/drive/v3/files/abc%2Fdef?fields=id%2Cname%2Cparents")
        XCTAssertNil(DriveAPI.fileRequest(id: ""))
    }

    func testTermsComeOnlyFromPlainWordQueries() {
        let home = "/Users/me"
        XCTAssertEqual(DriveResults.terms(for: SearchPlan.make("glaucoma drops", scope: .home, home: home, drives: [])), "glaucoma drops")
        XCTAssertNil(DriveResults.terms(for: SearchPlan.make("glaucoma kind:pdf", scope: .home, home: home, drives: [])))
        XCTAssertNil(DriveResults.terms(for: SearchPlan.make("", scope: .home, home: home, drives: [])))
    }

    // MARK: Responses

    func testListResponseIsParsed() throws {
        let list = try DriveAPI.parseList(Data(Self.listJSON.utf8))
        XCTAssertEqual(list.files.count, 3)
        let pdf = list.files[0]
        XCTAssertEqual(pdf.id, "f1")
        XCTAssertEqual(pdf.name, "Glaucoma review.pdf")
        XCTAssertEqual(pdf.size, 123_456, "sizes arrive as strings")
        XCTAssertEqual(pdf.parents, ["d2"])
        XCTAssertEqual(pdf.webViewLink?.absoluteString, "https://drive.google.com/file/d/f1/view")
        XCTAssertEqual(pdf.modifiedTime, Date(timeIntervalSince1970: 1_700_000_000.5))
        XCTAssertEqual(pdf.localName, "Glaucoma review.pdf")
        XCTAssertFalse(pdf.isNative)

        let doc = list.files[1]
        XCTAssertTrue(doc.isNative)
        XCTAssertNil(doc.size)
        XCTAssertEqual(doc.localName, "Notes.gdoc", "Docs show on disk as link files")
        XCTAssertEqual(list.files[2].localName, "Budget.gsheet")
        XCTAssertNil(list.files[2].modifiedTime, "a missing date is no date")
        XCTAssertEqual(list.nextPageToken, "next")
    }

    func testEmptyAndBrokenResponses() {
        XCTAssertEqual(try DriveAPI.parseList(Data("{}".utf8)).files, [])
        XCTAssertThrowsError(try DriveAPI.parseList(Data("<html>".utf8))) { XCTAssertEqual($0 as? DriveError, .badResponse) }
    }

    func testRateLimitReasons() {
        XCTAssertTrue(DriveAPI.isRateLimit(Data(#"{"error":{"errors":[{"reason":"userRateLimitExceeded"}],"code":403}}"#.utf8)))
        XCTAssertTrue(DriveAPI.isRateLimit(Data(#"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#.utf8)))
        XCTAssertFalse(DriveAPI.isRateLimit(Data(#"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#.utf8)))
        XCTAssertFalse(DriveAPI.isRateLimit(Data()))
    }

    // MARK: Client

    func testUnauthorizedRefreshesOnceAndRetries() async throws {
        let transport = MockTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh"
                ? (200, Self.listJSON, [:]) : (401, "{}", [:])
        }
        let tokens = StubTokens()
        let client = DriveClient(transport: transport, tokens: tokens)
        let files = try await client.search("glaucoma")
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(transport.count, 2)
        XCTAssertEqual(tokens.refreshes, 1)
    }

    func testRateLimitsPauseRequestsWithoutTheNetwork() async throws {
        let clock = TestClock()
        let transport = MockTransport { _ in (429, #"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#, ["Retry-After": "5"]) }
        let client = DriveClient(transport: transport, tokens: StubTokens(), now: { clock.now })
        await XCTAssertThrowsAsync(try await client.search("a")) { error in
            guard case .rateLimited(let until)? = error as? DriveError else { return XCTFail("\(error)") }
            XCTAssertEqual(until, clock.now.addingTimeInterval(5))
        }
        await XCTAssertThrowsAsync(try await client.search("a")) { XCTAssertNotNil($0 as? DriveError) }
        XCTAssertEqual(transport.count, 1, "while paused, nothing is sent")
        clock.now = clock.now.addingTimeInterval(6)
        await XCTAssertThrowsAsync(try await client.search("a")) { _ in }
        XCTAssertEqual(transport.count, 2)
    }

    func testRefusedForbiddenIsNotARateLimit() async {
        let transport = MockTransport { _ in (403, #"{"error":{"errors":[{"reason":"insufficientPermissions"}]}}"#, [:]) }
        let client = DriveClient(transport: transport, tokens: StubTokens())
        await XCTAssertThrowsAsync(try await client.search("a")) { XCTAssertEqual($0 as? DriveError, .http(403)) }
        let pause = await client.pause
        XCTAssertNil(pause)
    }

    // MARK: Parent paths

    func testParentsAreWalkedUpToMyDrive() async {
        let resolver = DrivePathResolver(lookup: Self.folders.lookup)
        let pdf = DriveFile(id: "f1", name: "Glaucoma review.pdf", mimeType: "application/pdf", parents: ["d2"])
        let components = await resolver.components(of: pdf)
        XCTAssertEqual(components, ["01 Research", "Glaucoma", "Glaucoma review.pdf"])
        let doc = DriveFile(id: "f2", name: "Notes", mimeType: "application/vnd.google-apps.document", parents: ["root-id"])
        let top = await resolver.components(of: doc)
        XCTAssertEqual(top, ["Notes.gdoc"])
    }

    func testFolderLookupsAreCachedForTheSession() async {
        let folders = Self.folders
        let resolver = DrivePathResolver(lookup: folders.lookup)
        let a = DriveFile(id: "a", name: "a.pdf", mimeType: "application/pdf", parents: ["d2"])
        let b = DriveFile(id: "b", name: "b.pdf", mimeType: "application/pdf", parents: ["d2"])
        _ = await resolver.components(of: a)
        _ = await resolver.components(of: b)
        let lookups = await resolver.lookups
        XCTAssertEqual(lookups, 2, "d2 and d1 once each")
        XCTAssertEqual(folders.calls(for: "d2"), 1)
        XCTAssertEqual(folders.calls(for: "root"), 1)
    }

    func testFilesOutsideMyDriveHaveNoPath() async {
        let resolver = DrivePathResolver(lookup: Self.folders.lookup)
        let shared = DriveFile(id: "s", name: "Shared.pdf", mimeType: "application/pdf", parents: ["elsewhere"])
        let none = await resolver.components(of: shared)
        XCTAssertNil(none, "a folder shared with you is not under My Drive")
        let orphan = DriveFile(id: "o", name: "Orphan.pdf", mimeType: "application/pdf", parents: [])
        let alsoNone = await resolver.components(of: orphan)
        XCTAssertNil(alsoNone)
        let lost = DriveFile(id: "l", name: "Lost.pdf", mimeType: "application/pdf", parents: ["missing"])
        let failed = await resolver.components(of: lost)
        XCTAssertNil(failed, "a lookup that fails gives no path")
    }

    func testLocalPathIsTheAccountThatHoldsTheFile() {
        let drives = ["/Users/me/Library/CloudStorage/GoogleDrive-a/My Drive", "/Users/me/Library/CloudStorage/GoogleDrive-b/My Drive"]
        let onDisk: Set<String> = ["/Users/me/Library/CloudStorage/GoogleDrive-b/My Drive/01 Research/x.pdf"]
        XCTAssertEqual(DriveResults.localPath(components: ["01 Research", "x.pdf"], myDrives: drives, exists: onDisk.contains),
                       "/Users/me/Library/CloudStorage/GoogleDrive-b/My Drive/01 Research/x.pdf")
        XCTAssertNil(DriveResults.localPath(components: ["y.pdf"], myDrives: drives, exists: onDisk.contains))
        XCTAssertNil(DriveResults.localPath(components: [], myDrives: drives, exists: { _ in true }))
    }

    // MARK: De-duplication

    func testFilesAlreadyInLocalResultsAreDropped() {
        let local = "/Users/me/Library/CloudStorage/GoogleDrive-a/My Drive/x.pdf"
        let hits = [
            DriveHit(file: DriveFile(id: "1", name: "x.pdf", mimeType: "application/pdf"), localPath: local),
            DriveHit(file: DriveFile(id: "2", name: "y.pdf", mimeType: "application/pdf"), localPath: "/Users/me/Library/CloudStorage/GoogleDrive-a/My Drive/y.pdf"),
            DriveHit(file: DriveFile(id: "3", name: "web.pdf", mimeType: "application/pdf"), localPath: nil),
            DriveHit(file: DriveFile(id: "2", name: "y.pdf", mimeType: "application/pdf"), localPath: nil),
        ]
        let kept = DriveResults.dedupe(hits, local: [local])
        XCTAssertEqual(kept.map(\.id), ["2", "3"], "the local copy wins, and each file shows once")
        XCTAssertEqual(DriveResults.dedupe(hits, local: ["/Users/me/Library/CloudStorage/GoogleDrive-a/My Drive/./x.pdf"]).map(\.id), ["2", "3"])
    }

    func testDecomposedNamesStillMatch() {
        let composed = "/Users/me/My Drive/Caf\u{E9}.pdf"
        let decomposed = "/Users/me/My Drive/Cafe\u{301}.pdf"
        let hit = DriveHit(file: DriveFile(id: "1", name: "Café.pdf", mimeType: "application/pdf"), localPath: composed)
        XCTAssertTrue(DriveResults.dedupe([hit], local: [decomposed]).isEmpty)
    }

    func testOpenTargets() {
        let link = URL(string: "https://drive.google.com/file/d/1/view")!
        let file = DriveFile(id: "1", name: "x.pdf", mimeType: "application/pdf", webViewLink: link)
        XCTAssertEqual(DriveHit(file: file, localPath: "/d/x.pdf").target, .file("/d/x.pdf"))
        XCTAssertEqual(DriveHit(file: file, localPath: nil).target, .web(link))
        let folder = DriveFile(id: "2", name: "F", mimeType: DriveFile.folderType)
        XCTAssertEqual(DriveHit(file: folder, localPath: "/d/F").target, .folder("/d/F"))
        XCTAssertNil(DriveHit(file: folder, localPath: nil).target)
    }

    // MARK: End to end, mocked

    func testSearchResolvesPathsAndDropsLocalCopies() async throws {
        let myDrive = "/Users/me/Library/CloudStorage/GoogleDrive-a/My Drive"
        let transport = MockTransport { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/drive/v3/files": return (200, Self.listJSON, [:])
            case "/drive/v3/files/root": return (200, #"{"id":"root-id"}"#, [:])
            case "/drive/v3/files/d2": return (200, #"{"id":"d2","name":"Glaucoma","parents":["d1"]}"#, [:])
            case "/drive/v3/files/d1": return (200, #"{"id":"d1","name":"01 Research","parents":["root-id"]}"#, [:])
            default: return (404, "{}", [:])
            }
        }
        let client = DriveClient(transport: transport, tokens: StubTokens())
        let resolver = DrivePathResolver(lookup: { id, fields in try await client.file(id, fields: fields) })
        let onDisk: Set<String> = [myDrive + "/01 Research/Glaucoma/Glaucoma review.pdf", myDrive + "/Notes.gdoc"]
        let engine = DriveSearchEngine(client: client, resolver: resolver, myDrives: { [myDrive] }, exists: { onDisk.contains($0) })
        let hits = try await engine.search("glaucoma")
        XCTAssertEqual(hits.map(\.id), ["f1", "f2", "f3"], "Drive's order is kept")
        XCTAssertEqual(hits[0].localPath, myDrive + "/01 Research/Glaucoma/Glaucoma review.pdf")
        XCTAssertEqual(hits[1].localPath, myDrive + "/Notes.gdoc")
        XCTAssertNil(hits[2].localPath, "not on disk: opens on the web")
        XCTAssertEqual(hits[2].target, .web(URL(string: "https://docs.google.com/spreadsheets/d/f3/edit")!))

        let shown = DriveResults.dedupe(hits, local: [myDrive + "/01 Research/Glaucoma/Glaucoma review.pdf"])
        XCTAssertEqual(shown.map(\.id), ["f2", "f3"])
        XCTAssertEqual(transport.paths.filter { $0 == "/drive/v3/files/d2" }.count, 1)
        XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer stale" })
    }

    func testNoAccountOnThisMacMeansNoPaths() async throws {
        let transport = MockTransport { _ in (200, Self.listJSON, [:]) }
        let client = DriveClient(transport: transport, tokens: StubTokens())
        let resolver = DrivePathResolver(lookup: { id, fields in try await client.file(id, fields: fields) })
        let engine = DriveSearchEngine(client: client, resolver: resolver, myDrives: { [] }, exists: { _ in true })
        let hits = try await engine.search("glaucoma")
        XCTAssertEqual(hits.compactMap(\.localPath), [])
        XCTAssertEqual(transport.count, 1, "no folder lookups without a Drive folder to map them to")
    }

    // MARK: OAuth

    func testClientFileInEitherShape() {
        let flat = GoogleOAuthConfig.parse(Data(#"{"client_id": "id-1.apps.googleusercontent.com", "client_secret": "s"}"#.utf8))
        XCTAssertEqual(flat, GoogleOAuthConfig(clientID: "id-1.apps.googleusercontent.com", clientSecret: "s"))
        let downloaded = GoogleOAuthConfig.parse(Data(#"{"installed": {"client_id": "id-2", "client_secret": "t", "redirect_uris": ["http://localhost"]}}"#.utf8))
        XCTAssertEqual(downloaded?.clientID, "id-2")
        XCTAssertNil(GoogleOAuthConfig.parse(Data(#"{"client_secret": "s"}"#.utf8)))
        XCTAssertNil(GoogleOAuthConfig.parse(Data("not json".utf8)))
        XCTAssertEqual(GoogleOAuthConfig.location(home: URL(fileURLWithPath: "/Users/me")).path, "/Users/me/.config/grand-line/google-oauth.json")
    }

    func testPKCEChallengeIsS256() {
        // RFC 7636, appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let made = PKCE.make()
        XCTAssertEqual(made.verifier.count, 64)
        XCTAssertNotEqual(made.verifier, PKCE.make().verifier)
    }

    func testConsentURLAsksForReadOnlyDriveWithPKCE() throws {
        let config = GoogleOAuthConfig(clientID: "id-1", clientSecret: "s")
        let pkce = PKCE(verifier: "v")
        let url = GoogleOAuth.authorizationURL(config: config, redirectURI: GoogleOAuth.redirectURI(port: 53_682), pkce: pkce, state: "st")
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.google.com")
        XCTAssertEqual(items["scope"], "https://www.googleapis.com/auth/drive.readonly")
        XCTAssertEqual(items["redirect_uri"], "http://127.0.0.1:53682")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], pkce.challenge)
        XCTAssertEqual(items["access_type"], "offline")
        XCTAssertEqual(items["state"], "st")
    }

    func testLoopbackRedirectIsRead() {
        let ok = GoogleOAuth.callback(fromRequest: "GET /?state=st&code=4%2F0Ab&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        XCTAssertEqual(ok, GoogleOAuth.Callback(code: "4/0Ab", state: "st", error: nil))
        let refused = GoogleOAuth.callback(fromRequest: "GET /?error=access_denied&state=st HTTP/1.1\r\n\r\n")
        XCTAssertEqual(refused?.error, "access_denied")
        XCTAssertNil(GoogleOAuth.callback(fromRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n"))
        XCTAssertNil(GoogleOAuth.callback(fromRequest: "POST /?code=x HTTP/1.1\r\n\r\n"))
    }

    func testCodeExchangeSendsTheVerifier() throws {
        let config = GoogleOAuthConfig(clientID: "id-1", clientSecret: "s")
        let request = GoogleOAuth.codeExchange(config: config, code: "c/1", pkce: PKCE(verifier: "v"), redirectURI: "http://127.0.0.1:9")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("code=c%2F1"))
        XCTAssertTrue(body.contains("code_verifier=v"))
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A9"))
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testAccessTokensAreRefreshedOnceAndKept() async throws {
        let clock = TestClock()
        let transport = MockTransport { _ in (200, #"{"access_token":"a1","expires_in":3600}"#, [:]) }
        let tokens = DriveTokens(config: GoogleOAuthConfig(clientID: "id", clientSecret: "s"), transport: transport,
                                 refreshToken: { "r1" }, now: { clock.now })
        async let first = tokens.accessToken(refresh: false)
        async let second = tokens.accessToken(refresh: false)
        let both = try await [first, second]
        XCTAssertEqual(both, ["a1", "a1"])
        XCTAssertEqual(transport.count, 1, "one refresh for two callers")
        _ = try await tokens.accessToken(refresh: false)
        XCTAssertEqual(transport.count, 1, "kept until it nears expiry")
        clock.now = clock.now.addingTimeInterval(3_590)
        _ = try await tokens.accessToken(refresh: false)
        XCTAssertEqual(transport.count, 2)
    }

    func testARefusedRefreshTokenAsksToReconnect() async {
        let transport = MockTransport { _ in (400, #"{"error":"invalid_grant"}"#, [:]) }
        let tokens = DriveTokens(config: GoogleOAuthConfig(clientID: "id", clientSecret: "s"), transport: transport, refreshToken: { "r1" })
        await XCTAssertThrowsAsync(try await tokens.accessToken(refresh: false)) { XCTAssertEqual($0 as? DriveError, .needsReconnect) }
        let none = DriveTokens(config: GoogleOAuthConfig(clientID: "id", clientSecret: "s"), transport: transport, refreshToken: { nil })
        await XCTAssertThrowsAsync(try await none.accessToken(refresh: false)) { XCTAssertEqual($0 as? DriveError, .notConnected) }
    }

    // MARK: Fixtures

    static let listJSON = """
    {"nextPageToken": "next", "files": [
      {"id": "f1", "name": "Glaucoma review.pdf", "mimeType": "application/pdf", "modifiedTime": "2023-11-14T22:13:20.500Z",
       "size": "123456", "parents": ["d2"], "webViewLink": "https://drive.google.com/file/d/f1/view"},
      {"id": "f2", "name": "Notes", "mimeType": "application/vnd.google-apps.document", "modifiedTime": "2023-11-14T22:13:20Z",
       "parents": ["root-id"], "webViewLink": "https://docs.google.com/document/d/f2/edit"},
      {"id": "f3", "name": "Budget", "mimeType": "application/vnd.google-apps.spreadsheet",
       "parents": ["elsewhere"], "webViewLink": "https://docs.google.com/spreadsheets/d/f3/edit"}
    ]}
    """

    /// My Drive (root-id) > 01 Research (d1) > Glaucoma (d2), for the resolver.
    static var folders: FolderTable {
        FolderTable([
            "root": DriveFile(id: "root-id", name: "My Drive", mimeType: DriveFile.folderType),
            "d1": DriveFile(id: "d1", name: "01 Research", mimeType: DriveFile.folderType, parents: ["root-id"]),
            "d2": DriveFile(id: "d2", name: "Glaucoma", mimeType: DriveFile.folderType, parents: ["d1"]),
            "elsewhere": DriveFile(id: "elsewhere", name: "Shared folder", mimeType: DriveFile.folderType),
        ])
    }
}

/// Answers requests from a closure and records them.
final class MockTransport: DriveTransport, @unchecked Sendable {
    typealias Answer = (status: Int, body: String, headers: [String: String])
    private let answer: @Sendable (URLRequest) -> Answer
    private let lock = NSLock()
    private var sent: [URLRequest] = []

    init(_ answer: @escaping @Sendable (URLRequest) -> Answer) {
        self.answer = answer
    }

    var requests: [URLRequest] { lock.withLock { sent } }
    var count: Int { requests.count }
    var paths: [String] { requests.map { $0.url?.path ?? "" } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(request) }
        let reply = answer(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }
}

/// "stale" until a refresh is asked for, then "fresh".
final class StubTokens: DriveTokenSource, @unchecked Sendable {
    private let lock = NSLock()
    private var refreshed = 0

    var refreshes: Int { lock.withLock { refreshed } }

    func accessToken(refresh: Bool) async throws -> String {
        lock.withLock {
            if refresh { refreshed += 1 }
            return refreshed > 0 ? "fresh" : "stale"
        }
    }
}

/// Folders by id, counting lookups.
final class FolderTable: @unchecked Sendable {
    private let files: [String: DriveFile]
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(_ files: [String: DriveFile]) {
        self.files = files
    }

    func calls(for id: String) -> Int { lock.withLock { counts[id] ?? 0 } }

    var lookup: DrivePathResolver.Lookup {
        { [self] id, _ in
            lock.withLock { counts[id, default: 0] += 1 }
            guard let file = files[id] else { throw DriveError.http(404) }
            return file
        }
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

func XCTAssertThrowsAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line,
                             _ check: (Error) -> Void) async {
    do {
        _ = try await expression()
        XCTFail("expected an error", file: file, line: line)
    } catch {
        check(error)
    }
}
