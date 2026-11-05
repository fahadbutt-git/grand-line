import AppKit
import BrowserKit
import FileKit
import Foundation

/// The Google Drive account Nexus searches inside: the person's own OAuth
/// client (~/.config/grand-line/google-oauth.json), sign-in in the default
/// browser with PKCE and a loopback redirect, the refresh token in the
/// Keychain, and access tokens refreshed as they expire.
@MainActor
final class GoogleDriveAccount: ObservableObject {
    static let shared = GoogleDriveAccount()

    enum Status: Equatable {
        /// No client file yet: the help sheet explains how to make one.
        case notSetUp
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var status: Status = .notSetUp
    /// Bumped whenever the account changes, so searches start again.
    @Published private(set) var generation = 0

    private let home: URL
    private let transport = URLSessionTransport()
    private var config: GoogleOAuthConfig?
    private var tokens: DriveTokens?
    private(set) var engine: DriveSearchEngine?
    private var server: LoopbackServer?
    private var connectTask: Task<Void, Never>?

    init(home: URL = HomeFolder.url) {
        self.home = home
        reload()
    }

    var configLocation: URL { GoogleOAuthConfig.location(home: home) }

    /// Reads the client file again (it may have been saved since) and whether
    /// a refresh token is stored.
    func reload() {
        guard status != .connecting else { return }
        let config = GoogleOAuthConfig.load(home: home)
        let changed = config != self.config
        self.config = config
        let next: Status
        if config == nil {
            next = .notSetUp
        } else if DriveKeychain.read() != nil {
            next = .connected
        } else {
            next = .disconnected
        }
        if next == .connected, engine == nil || changed, let config { makeEngine(config) }
        if next != .connected { engine = nil; tokens = nil }
        if next != status { status = next; generation += 1 }
    }

    private func makeEngine(_ config: GoogleOAuthConfig) {
        let tokens = DriveTokens(config: config, transport: transport, refreshToken: { DriveKeychain.read() })
        let client = DriveClient(transport: transport, tokens: tokens)
        let resolver = DrivePathResolver(lookup: { id, fields in try await client.file(id, fields: fields) })
        let home = self.home
        engine = DriveSearchEngine(
            client: client, resolver: resolver,
            myDrives: { GoogleDrive.accounts(home: home).map { $0.myDrive.standardizedFileURL.path } },
            exists: { FileManager.default.fileExists(atPath: $0) }
        )
        self.tokens = tokens
    }

    /// Opens Google's consent page in the default browser and waits for the
    /// code on the loopback address. Nothing is shown if it fails: the
    /// account stays disconnected.
    func connect() {
        reload()
        guard let config, status != .connecting else { return }
        status = .connecting
        connectTask = Task { [weak self] in
            let result = await Self.signIn(config: config, transport: self?.transport ?? URLSessionTransport(), server: { self?.server = $0 })
            guard let self else { return }
            self.server = nil
            self.status = .disconnected
            if let tokens = result, let refresh = tokens.refreshToken, DriveKeychain.save(refresh) {
                self.reload()
                await self.tokens?.seed(tokens)
                NexusLog.note("google drive: connected")
            } else {
                NexusLog.note("google drive: sign-in did not finish")
                self.reload()
            }
            self.generation += 1
        }
    }

    private static func signIn(config: GoogleOAuthConfig, transport: DriveTransport,
                               server keep: @MainActor (LoopbackServer) -> Void) async -> GoogleTokens? {
        guard let server = try? LoopbackServer() else { return nil }
        keep(server)
        defer { server.stop() }
        guard let port = try? await server.start(), port != 0 else { return nil }
        let redirect = GoogleOAuth.redirectURI(port: port)
        let pkce = PKCE.make()
        let state = PKCE.randomString(32)
        let url = GoogleOAuth.authorizationURL(config: config, redirectURI: redirect, pkce: pkce, state: state)
        NSWorkspace.shared.open(url)
        guard let callback = try? await server.callback(timeout: 300), callback.state == state, let code = callback.code else { return nil }
        let request = GoogleOAuth.codeExchange(config: config, code: code, pkce: pkce, redirectURI: redirect)
        guard let reply = try? await transport.send(request), (200..<300).contains(reply.1.statusCode) else { return nil }
        return try? GoogleOAuth.parseTokens(reply.0)
    }

    /// Stops a sign-in that is waiting for the browser.
    func cancelConnect() {
        connectTask?.cancel()
        server?.stop()
    }

    /// Revokes the token with Google and deletes it from the Keychain.
    func disconnect() {
        let stored = DriveKeychain.read()
        DriveKeychain.delete()
        engine = nil
        tokens = nil
        reload()
        generation += 1
        guard let stored else { return }
        let transport = self.transport
        Task.detached {
            _ = try? await transport.send(GoogleOAuth.revoke(token: stored))
        }
    }

    /// The account's refresh token was refused: it is forgotten, and the
    /// section offers to connect again.
    func tokenRefused() {
        DriveKeychain.delete()
        reload()
    }

    /// Opens Google Cloud Console's credentials page.
    static let consoleURL = URL(string: "https://console.cloud.google.com/apis/credentials")!
    static let driveAPIURL = URL(string: "https://console.cloud.google.com/apis/library/drive.googleapis.com")!
}
