import BrowserKit
import Foundation

/// What the "Found in Google Drive" section shows for a search.
enum DriveSection: Equatable {
    case hidden
    /// No client file, or no account connected: one quiet row that connects.
    case connect
    /// Waiting for the browser sign-in.
    case connecting
    case searching
    case results([DriveHit])
    /// One quiet line, never an alert (a rate limit).
    case note(String)
}

/// Runs the Drive half of a search beside the local one. It starts a moment
/// after the local search (the search field has already waited for typing to
/// pause), is cancelled when the query changes, and never holds up local
/// results: they are shown as they come, and Drive's join them below.
/// Offline or failing, it shows nothing.
@MainActor
final class DriveSearchRunner {
    /// The search field waits 200 ms after the last key; this brings Drive's
    /// request to about 250 ms after typing stops.
    static let delay: UInt64 = 50_000_000

    private var task: Task<Void, Never>?

    func start(terms: String?, update: @escaping (DriveSection) -> Void) {
        task?.cancel()
        task = nil
        guard let terms else { update(.hidden); return }
        let account = GoogleDriveAccount.shared
        if account.status != .connected { account.reload() }
        switch account.status {
        case .notSetUp, .disconnected:
            update(.connect)
            return
        case .connecting:
            update(.connecting)
            return
        case .connected:
            break
        }
        guard let engine = account.engine else { update(.hidden); return }
        update(.searching)
        task = Task { [weak account] in
            try? await Task.sleep(nanoseconds: Self.delay)
            guard !Task.isCancelled else { return }
            do {
                let hits = try await engine.search(terms)
                guard !Task.isCancelled else { return }
                update(.results(hits))
            } catch DriveError.needsReconnect {
                guard !Task.isCancelled else { return }
                NexusLog.note("google drive: the stored sign-in was refused")
                account?.tokenRefused()
                update(.connect)
            } catch DriveError.notConnected {
                guard !Task.isCancelled else { return }
                update(.connect)
            } catch DriveError.rateLimited {
                guard !Task.isCancelled else { return }
                update(.note("Google Drive asked Nexus to slow down. Its results will be back shortly."))
            } catch {
                // Offline, a timeout, a server error: the section stays out of the way.
                guard !Task.isCancelled else { return }
                update(.hidden)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
