import Foundation
import IndexKit
import IndexService

/// The name index of the home folder (without ~/Library, but with Google Drive
/// in ~/Library/CloudStorage). Sight no longer keeps one of its own: it asks the
/// Grand Line Index service, which Nexus shares, and which is already current
/// when the panel opens. While the service is out of reach, answers come from a
/// copy read from the service's snapshot (see SharedIndexClient).
final class NameIndex: IndexStatusProviding, @unchecked Sendable {
    /// Sight's own snapshot from before the service. The service adopts it on
    /// its first start; Sight no longer writes it.
    let snapshot: URL
    let root: String
    let client: SharedIndexClient

    init(snapshot: URL, root: String) {
        self.snapshot = snapshot
        self.root = root
        self.client = SharedIndexClient(home: root)
    }

    /// Connects to the service at launch, before the window is first shown.
    /// Nothing runs on a timer after that: the connection stays open by
    /// itself, and `warm()` (the window opening) mends a dropped one.
    func start() {
        client.start()
        // A first reading, so the first search can already explain missing folders.
        _ = Task.detached(priority: .utility) { [weak self] in
            _ = await self?.unreadable()
        }
    }

    private var gate = WarmGate()

    /// Reconnects if the connection was dropped (the window is opening), at
    /// most once a minute.
    func warm() {
        lock.lock()
        let due = gate.shouldWarm()
        lock.unlock()
        if due { client.warm() }
    }

    /// A search answered from the local copy because the service was slow
    /// got the service's answer later: the window searches again.
    func onLateAnswer(_ handler: @escaping @Sendable () -> Void) {
        client.onLateAnswer(handler)
    }

    func search(_ text: String, limit: Int) async -> [IndexMatch] {
        await client.search(text, limit: limit)
    }

    /// Folders macOS would not let the index read. Asked for with every file
    /// search, so it answers from the last reading and reads again in the
    /// background at most every few seconds, never holding up the results.
    func unreadable() async -> [String] {
        let now = Date()
        lock.lock()
        let known = knownUnreadable
        let stale = now.timeIntervalSince(lastRead) > 5
        if stale { lastRead = now }
        lock.unlock()
        if stale {
            let client = self.client
            Task.detached(priority: .utility) { [weak self] in
                let folders = await client.unreadable()
                self?.keep(folders)
            }
        }
        return known
    }

    private let lock = NSLock()
    private var knownUnreadable: [String] = []
    private var lastRead = Date.distantPast

    private func keep(_ folders: [String]) {
        lock.lock()
        knownUnreadable = folders
        lock.unlock()
    }

    func noteOpened(_ path: String) {
        client.noteOpened(path)
    }

    /// The service saves the index; nothing to do here.
    func save() {}

    func status() async -> IndexStatus {
        await client.status()
    }

    func rebuild() async {
        await client.rebuild()
    }
}
