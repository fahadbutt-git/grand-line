import Foundation

/// A file from the Google Drive API v3 (`files.list`, `files.get`), with the
/// fields the "Found in Google Drive" section asks for.
public struct DriveFile: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let modifiedTime: Date?
    public let size: Int64?
    public let parents: [String]
    public let webViewLink: URL?

    public init(id: String, name: String, mimeType: String, modifiedTime: Date? = nil, size: Int64? = nil,
                parents: [String] = [], webViewLink: URL? = nil) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.modifiedTime = modifiedTime
        self.size = size
        self.parents = parents
        self.webViewLink = webViewLink
    }

    enum CodingKeys: String, CodingKey {
        case id, name, mimeType, modifiedTime, size, parents, webViewLink
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? ""
        modifiedTime = (try c.decodeIfPresent(String.self, forKey: .modifiedTime)).flatMap(DriveAPI.date)
        // Drive sends sizes as strings ("int64" in its discovery document).
        if let text = try? c.decodeIfPresent(String.self, forKey: .size) {
            size = Int64(text)
        } else {
            size = try? c.decodeIfPresent(Int64.self, forKey: .size)
        }
        parents = try c.decodeIfPresent([String].self, forKey: .parents) ?? []
        webViewLink = (try c.decodeIfPresent(String.self, forKey: .webViewLink)).flatMap(URL.init(string:))
    }

    public static let folderType = "application/vnd.google-apps.folder"

    public var isFolder: Bool { mimeType == Self.folderType }

    /// A Google Docs, Sheets or Slides file (or another type stored only in
    /// Drive), which Drive for desktop shows as a small link file.
    public var isNative: Bool { mimeType.hasPrefix("application/vnd.google-apps.") && !isFolder }

    /// The extension Drive for desktop gives a native file's link file:
    /// Name.gdoc, Name.gsheet, Name.gslides. Nil for other files.
    public var linkExtension: String? {
        let table: [String: String] = [
            "application/vnd.google-apps.document": "gdoc",
            "application/vnd.google-apps.spreadsheet": "gsheet",
            "application/vnd.google-apps.presentation": "gslides",
            "application/vnd.google-apps.drawing": "gdraw",
            "application/vnd.google-apps.form": "gform",
            "application/vnd.google-apps.jam": "gjam",
            "application/vnd.google-apps.map": "gmap",
            "application/vnd.google-apps.site": "gsite",
            "application/vnd.google-apps.script": "gscript",
            "application/vnd.google-apps.table": "gtable",
        ]
        return table[mimeType]
    }

    /// The name Drive for desktop shows on disk.
    public var localName: String {
        // Drive allows "/" in a name; a Mac file name cannot hold it.
        let safe = name.replacingOccurrences(of: "/", with: ":")
        guard let ext = linkExtension else { return safe }
        return safe + "." + ext
    }

    /// A plain description of the type, for the row's Kind.
    public var kindTitle: String {
        switch mimeType {
        case Self.folderType: return "Folder"
        case "application/vnd.google-apps.document": return "Google Docs"
        case "application/vnd.google-apps.spreadsheet": return "Google Sheets"
        case "application/vnd.google-apps.presentation": return "Google Slides"
        case "application/pdf": return "PDF document"
        default:
            if isNative { return "Google Drive file" }
            let ext = (name as NSString).pathExtension
            return ext.isEmpty ? "Document" : ext.uppercased() + " file"
        }
    }
}

/// One page of `files.list`.
public struct DriveFileList: Decodable, Equatable, Sendable {
    public let files: [DriveFile]
    public let nextPageToken: String?

    public init(files: [DriveFile], nextPageToken: String? = nil) {
        self.files = files
        self.nextPageToken = nextPageToken
    }

    enum CodingKeys: String, CodingKey { case files, nextPageToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = try c.decodeIfPresent([DriveFile].self, forKey: .files) ?? []
        nextPageToken = try c.decodeIfPresent(String.self, forKey: .nextPageToken)
    }
}

/// What went wrong talking to Drive. None of it is shown as an alert.
public enum DriveError: Error, Equatable, Sendable {
    /// No client ID file, or no account connected.
    case notConnected
    /// The refresh token was refused (revoked, or expired); connect again.
    case needsReconnect
    /// 403 rate limits and 429: wait until the date.
    case rateLimited(until: Date)
    case http(Int)
    case badResponse
}

/// The Drive API v3: building requests and reading responses.
public enum DriveAPI {
    public static let base = URL(string: "https://www.googleapis.com/drive/v3/")!
    public static let listFields = "files(id,name,mimeType,modifiedTime,size,parents,webViewLink),nextPageToken"
    public static let folderFields = "id,name,parents"
    public static let pageSize = 25

    /// A string for a Drive query's single quotes: backslashes and quotes
    /// escaped with a backslash, as the API asks.
    public static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            if character == "\\" || character == "'" { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// The search words as one fullText query over files not in the Trash.
    /// Nil when there is nothing to look for.
    public static func fullTextQuery(_ terms: String) -> String? {
        let words = terms.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        return "fullText contains '\(escape(words))' and trashed = false"
    }

    public static func searchRequest(terms: String, pageSize: Int = DriveAPI.pageSize) -> URLRequest? {
        guard let q = fullTextQuery(terms) else { return nil }
        let query = formEncoded([
            ("q", q), ("fields", listFields), ("pageSize", String(pageSize)), ("corpora", "user"), ("spaces", "drive"),
        ])
        guard let url = URL(string: base.absoluteString + "files?" + query) else { return nil }
        return get(url)
    }

    /// Name=value pairs with everything but RFC 3986's unreserved characters
    /// percent-encoded, so "+", "&" and "=" in a search reach Drive as typed.
    public static func formEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(percentEncoded($0.0))=\(percentEncoded($0.1))" }.joined(separator: "&")
    }

    public static func percentEncoded(_ text: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// `files.get` for a folder's name and parents ("root" for My Drive's own id).
    public static func fileRequest(id: String, fields: String = folderFields) -> URLRequest? {
        guard !id.isEmpty,
              let url = URL(string: base.absoluteString + "files/" + percentEncoded(id) + "?" + formEncoded([("fields", fields)])) else { return nil }
        return get(url)
    }

    private static func get(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public static func parseList(_ data: Data) throws -> DriveFileList {
        do { return try JSONDecoder().decode(DriveFileList.self, from: data) } catch { throw DriveError.badResponse }
    }

    public static func parseFile(_ data: Data) throws -> DriveFile {
        do { return try JSONDecoder().decode(DriveFile.self, from: data) } catch { throw DriveError.badResponse }
    }

    /// Whether a 403 is a rate limit (Drive's usage limits) rather than a
    /// refusal, from its error reason.
    public static func isRateLimit(_ data: Data) -> Bool {
        struct Body: Decodable {
            struct Inner: Decodable {
                struct Item: Decodable { let reason: String? }
                let errors: [Item]?
                let status: String?
            }
            let error: Inner?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data), let error = body.error else { return false }
        if error.status == "RESOURCE_EXHAUSTED" { return true }
        let reasons = Set((error.errors ?? []).compactMap(\.reason))
        return !reasons.isDisjoint(with: ["rateLimitExceeded", "userRateLimitExceeded", "dailyLimitExceeded", "quotaExceeded"])
    }

    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// The HTTP layer, so tests can answer without a network.
public protocol DriveTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession, with no cache and no cookies.
public struct URLSessionTransport: DriveTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DriveError.badResponse }
        return (data, http)
    }
}

/// Access tokens for the Drive API.
public protocol DriveTokenSource: Sendable {
    /// A current access token; `refresh` asks for a new one (after a 401).
    func accessToken(refresh: Bool) async throws -> String
}
