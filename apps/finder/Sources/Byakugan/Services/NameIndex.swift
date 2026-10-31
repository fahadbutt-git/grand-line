import Foundation
import IndexKit
import LauncherKit

/// The name index of the home folder (without ~/Library, but with Google Drive
/// in ~/Library/CloudStorage), loaded from its snapshot at launch, kept current
/// with FSEvents and saved again on quit. On a first launch it can be searched
/// while it is built: Downloads, Desktop and Documents first, Google Drive last,
/// with the snapshot saved along the way.
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let exclusions = HomeIndexScope.exclusions(home: root)
            let order = ScanOrder.home(root)
            let index = (try? FileIndex.load(from: snapshot, exclusions: exclusions, order: order))
                ?? FileIndex(roots: [root], exclusions: exclusions, order: order)
            // Searchable at once: a saved index in full, a new one as it fills.
            self?.set(index)
            if await index.count == 0 || !(await index.isComplete) {
                await index.build(savingTo: snapshot, every: 30)
            }
            await index.startWatching()
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

    /// Folders macOS would not let the index read.
    func unreadable() async -> [String] {
        guard let index = current else { return [] }
        return await index.unreadable
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
