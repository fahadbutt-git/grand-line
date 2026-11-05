import CryptoKit
import Foundation

/// The person's own OAuth client for Google Drive, from
/// ~/.config/grand-line/google-oauth.json. Nexus carries no client ID of its
/// own. The file may hold the two keys at the top, or be the JSON that Google
/// Cloud Console downloads for a Desktop app (the keys under "installed").
public struct GoogleOAuthConfig: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    public static func location(home: URL) -> URL {
        home.appendingPathComponent(".config/grand-line/google-oauth.json")
    }

    public static func load(home: URL) -> GoogleOAuthConfig? {
        guard let data = try? Data(contentsOf: location(home: home)) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> GoogleOAuthConfig? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let keys = (object["installed"] as? [String: Any]) ?? object
        guard let id = (keys["client_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else { return nil }
        let secret = ((keys["client_secret"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return GoogleOAuthConfig(clientID: id, clientSecret: secret)
    }
}

/// A PKCE verifier and its S256 challenge (RFC 7636).
public struct PKCE: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
    }

    /// 64 random characters from the unreserved set.
    public static func make() -> PKCE {
        PKCE(verifier: randomString(64))
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func randomString(_ length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet[Int(generator.next(upperBound: UInt64(alphabet.count)))] })
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// The token endpoint's answer.
public struct GoogleTokens: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let expiresIn: TimeInterval
    public let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    public init(accessToken: String, expiresIn: TimeInterval, refreshToken: String?) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        expiresIn = try c.decodeIfPresent(TimeInterval.self, forKey: .expiresIn) ?? 3600
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}

/// OAuth 2.0 for installed apps: the consent page in the browser, the code
/// on a loopback address, PKCE, and the token endpoint.
public enum GoogleOAuth {
    /// Reading files' contents is what fullText search needs; metadata alone
    /// is not enough.
    public static let scope = "https://www.googleapis.com/auth/drive.readonly"
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    public static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)" }

    public static func authorizationURL(config: GoogleOAuthConfig, redirectURI: String, pkce: PKCE, state: String) -> URL {
        let query = DriveAPI.formEncoded([
            ("client_id", config.clientID),
            ("redirect_uri", redirectURI),
            ("response_type", "code"),
            ("scope", scope),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
            ("access_type", "offline"),
            ("prompt", "consent"),
        ])
        return URL(string: authorizationEndpoint.absoluteString + "?" + query)!
    }

    public static func codeExchange(config: GoogleOAuthConfig, code: String, pkce: PKCE, redirectURI: String) -> URLRequest {
        post(tokenEndpoint, [
            ("code", code),
            ("client_id", config.clientID),
            ("client_secret", config.clientSecret),
            ("code_verifier", pkce.verifier),
            ("redirect_uri", redirectURI),
            ("grant_type", "authorization_code"),
        ])
    }

    public static func refresh(config: GoogleOAuthConfig, refreshToken: String) -> URLRequest {
        post(tokenEndpoint, [
            ("client_id", config.clientID),
            ("client_secret", config.clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ])
    }

    public static func revoke(token: String) -> URLRequest {
        post(revokeEndpoint, [("token", token)])
    }

    private static func post(_ url: URL, _ pairs: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(DriveAPI.formEncoded(pairs.filter { !$0.1.isEmpty }).utf8)
        return request
    }

    /// What the browser brought back to the loopback address.
    public struct Callback: Equatable, Sendable {
        public var code: String?
        public var state: String?
        public var error: String?
    }

    /// Reads the request line of the redirect ("GET /?code=...&state=... HTTP/1.1").
    /// Nil for anything else (a favicon request, a stray connection).
    public static func callback(fromRequest head: String) -> Callback? {
        let line = head.components(separatedBy: .newlines).first ?? ""
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        guard let components = URLComponents(string: "http://127.0.0.1" + parts[1]), components.path == "/" || components.path.isEmpty else { return nil }
        var callback = Callback()
        for item in components.queryItems ?? [] {
            switch item.name {
            case "code": callback.code = item.value
            case "state": callback.state = item.value
            case "error": callback.error = item.value
            default: break
            }
        }
        guard callback.code != nil || callback.error != nil else { return nil }
        return callback
    }

    public static func parseTokens(_ data: Data) throws -> GoogleTokens {
        do { return try JSONDecoder().decode(GoogleTokens.self, from: data) } catch { throw DriveError.badResponse }
    }
}

/// Access tokens from the stored refresh token: kept until a minute before
/// they expire, refreshed one at a time however many searches ask at once.
public actor DriveTokens: DriveTokenSource {
    private let config: GoogleOAuthConfig
    private let transport: DriveTransport
    private let refreshToken: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private var current: (token: String, expires: Date)?
    private var refreshing: Task<String, Error>?

    public init(config: GoogleOAuthConfig, transport: DriveTransport,
                refreshToken: @escaping @Sendable () -> String?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = transport
        self.refreshToken = refreshToken
        self.now = now
    }

    /// A token from a fresh sign-in, used until it expires.
    public func seed(_ tokens: GoogleTokens) {
        current = (tokens.accessToken, now().addingTimeInterval(tokens.expiresIn))
    }

    public func accessToken(refresh: Bool) async throws -> String {
        if !refresh, let current, now().addingTimeInterval(60) < current.expires { return current.token }
        if let refreshing { return try await refreshing.value }
        guard let stored = refreshToken() else { throw DriveError.notConnected }
        let request = GoogleOAuth.refresh(config: config, refreshToken: stored)
        let transport = self.transport
        let task = Task<GoogleTokens, Error> {
            let (data, response) = try await transport.send(request)
            // 400 invalid_grant: the person revoked access or the token expired.
            if response.statusCode == 400 || response.statusCode == 401 { throw DriveError.needsReconnect }
            guard (200..<300).contains(response.statusCode) else { throw DriveError.http(response.statusCode) }
            return try GoogleOAuth.parseTokens(data)
        }
        let waiting = Task<String, Error> { try await task.value.accessToken }
        refreshing = waiting
        defer { refreshing = nil }
        let tokens = try await task.value
        current = (tokens.accessToken, now().addingTimeInterval(tokens.expiresIn))
        return tokens.accessToken
    }
}
