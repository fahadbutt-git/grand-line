import Foundation
import IndexKit
import LauncherKit

/// The name index of the home folder (without ~/Library, but with Google Drive
/// in ~/Library/CloudStorage), loaded from its snapshot at launch, kept current
/// with FSEvents and saved again on quit.
final class NameIndex: @unchecked Sendable {
    let snapshot: URL
    let root: String
    private var index: FileIndex?
    private let lock = NSLock()

    init(snapshot: URL, root: String) {
        self.snapshot = snapshot
        self.root = root
    }

    func start() {
        let snapshot = self.snapshot
        let root = self.root
        Task.detached(priority: .utility) { [weak self] in
            let exclusions = HomeIndexScope.exclusions(home: root)
            let index = (try? FileIndex.load(from: snapshot, exclusions: exclusions)) ?? FileIndex(roots: [root], exclusions: exclusions)
            if await index.count == 0 { await index.build() }
            await index.startWatching()
            self?.set(index)
        }
    }

    private func set(_ index: FileIndex) {
        lock.lock()
        self.index = index
        lock.unlock()
    }

    private var current: FileIndex? {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    func search(_ text: String, limit: Int) async -> [IndexMatch] {
        guard let index = current else { return [] }
        return await index.search(text, limit: limit)
    }

    func noteOpened(_ path: String) {
        guard let index = current else { return }
        Task { await index.noteOpened(path) }
    }

    func save() {
        guard let index = current else { return }
        let snapshot = self.snapshot
        Task.detached(priority: .utility) { try? await index.save(to: snapshot) }
    }
}
