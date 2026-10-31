import Foundation

/// An in-memory index of file and folder names under a set of root folders.
///
/// ```swift
/// let index = (try? FileIndex.load(from: snapshotURL)) ?? FileIndex(roots: [NSHomeDirectory()])
/// if await index.count == 0 { await index.build() }
/// await index.startWatching()
/// let matches = await index.search("gl rev", limit: 20)
/// ```
public actor FileIndex {
    public nonisolated let roots: [String]
    public nonisolated let exclusions: IndexExclusions

    var storage = IndexStorage()
    var folders: [String: Int32] = [:]
    var usage: [String: Usage] = [:]
    var lastEventID: UInt64
    var boostsRefreshed = Date.distantPast
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?

    /// Roots are resolved to real paths, and a root inside another root is dropped.
    public init(roots: [String], exclusions: IndexExclusions = .standard) {
        self.roots = FileIndex.distinctRoots(roots)
        self.exclusions = exclusions
        self.lastEventID = FolderWatcher.currentEventID
    }

    init(roots: [String], exclusions: IndexExclusions, storage: IndexStorage, usage: [String: Usage] = [:], lastEventID: UInt64) {
        self.roots = roots
        self.exclusions = exclusions
        self.storage = storage
        self.folders = storage.folderPaths()
        self.usage = usage
        self.lastEventID = lastEventID
    }

    deinit {
        watchTask?.cancel()
    }

    /// Files and folders in the index.
    public var count: Int { storage.liveCount }

    /// Scans every root from scratch.
    public func build() async {
        let roots = self.roots
        let exclusions = self.exclusions
        let started = FolderWatcher.currentEventID
        let built = await Task.detached(priority: .utility) {
            FolderScanner.build(roots: roots, exclusions: exclusions)
        }.value
        storage = built.storage
        folders = built.folders
        lastEventID = started
        refreshBoosts()
    }

    /// The best `limit` matches, best first.
    public func search(_ text: String, limit: Int = 50) async -> [IndexMatch] {
        guard limit > 0, let query = SearchQuery(text), storage.count > 0 else { return [] }
        if Date().timeIntervalSince(boostsRefreshed) > 3_600 { refreshBoosts() }
        let storage = self.storage
        let count = storage.count
        let chunks = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, count / 8_192 + 1))
        let size = (count + chunks - 1) / chunks
        var hits = await withTaskGroup(of: [Hit].self) { group in
            for chunk in 0..<chunks {
                let range = (chunk * size)..<min(count, (chunk + 1) * size)
                if range.isEmpty { continue }
                group.addTask { IndexSearch.scan(storage, query, range, limit: limit) }
            }
            var all: [Hit] = []
            for await part in group { all += part }
            return all
        }
        hits.sort(by: Hit.ranksBefore)
        return hits.prefix(limit).map { hit in
            let i = Int(hit.index)
            return IndexMatch(
                path: storage.path(i),
                name: storage.name(i),
                isFolder: storage.isFolder(i),
                tier: hit.tier,
                highlights: IndexSearch.highlights(storage, i, query)
            )
        }
    }

    /// Records an open, which lifts the path above equal matches from then on.
    public func noteOpened(_ path: String, at date: Date = Date()) {
        let path = FolderChange.normalize(path)
        var entry = usage[path] ?? Usage(count: 0, last: date)
        entry.count += 1
        entry.last = max(entry.last, date)
        usage[path] = entry
        if let index = index(of: path) {
            storage.boost[Int(index)] = entry.score(now: Date())
        }
    }

    /// Rescans the changed folders: only their direct contents, or everything below
    /// for a recursive change. New folders are scanned in full.
    public func apply(_ changes: [FolderChange]) {
        for change in FolderChange.coalesce(changes) {
            rescan(change.path, recursive: change.recursive)
        }
        if let watcher { lastEventID = max(lastEventID, watcher.latestEventID) }
        if storage.removedCount > 10_000, storage.removedCount * 4 > storage.count { compact() }
    }

    /// Follows changes with FSEvents, replaying what changed since the last build or snapshot.
    public func startWatching(latency: TimeInterval = 0.5) {
        guard watcher == nil else { return }
        let watcher = FolderWatcher(paths: roots, since: lastEventID, latency: latency)
        guard watcher.start() else { return }
        self.watcher = watcher
        let changes = watcher.changes
        watchTask = Task { [weak self] in
            for await batch in changes {
                await self?.apply(batch)
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }

    /// Writes the index, usage and the last event seen, for an instant start next time.
    public func save(to url: URL) throws {
        if storage.removedCount > 0 { compact() }
        if let watcher { lastEventID = max(lastEventID, watcher.latestEventID) }
        let snapshot = IndexSnapshot(roots: roots, storage: storage, usage: usage, lastEventID: lastEventID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try snapshot.encoded().write(to: url, options: .atomic)
    }

    /// Reads a saved index. Call `startWatching()` afterwards to catch up on changes.
    public static func load(from url: URL, exclusions: IndexExclusions = .standard) throws -> FileIndex {
        let snapshot = try IndexSnapshot(decoding: Data(contentsOf: url))
        let index = FileIndex(
            roots: snapshot.roots, exclusions: exclusions, storage: snapshot.storage,
            usage: snapshot.usage, lastEventID: snapshot.lastEventID
        )
        return index
    }

    // MARK: Updates

    func rescan(_ path: String, recursive: Bool) {
        guard let folder = folders[path] else {
            if let parent = nearestIndexedAncestor(of: path) { rescan(parent, recursive: false) }
            return
        }
        guard let listing = FolderScanner.list(path, exclusions: exclusions) else {
            if storage.isRoot(Int(folder)) {
                forget(storage.removeContents(of: folder))
            } else {
                forget(storage.remove(folder))
            }
            return
        }
        if recursive {
            forget(storage.removeContents(of: folder))
            for child in listing { add(child, in: path, at: folder) }
            return
        }
        let existing = storage.children(of: folder)
        var listed = Set<String>()
        for child in listing {
            listed.insert(child.name)
            if let old = existing[child.name] {
                if storage.isFolder(Int(old)) == child.isFolder { continue }
                forget(storage.remove(old))
            }
            add(child, in: path, at: folder)
        }
        for (name, old) in existing where !listed.contains(name) {
            forget(storage.remove(old))
        }
    }

    private func add(_ child: FolderScanner.Child, in path: String, at folder: Int32) {
        for (added, index) in FolderScanner.add(child, in: path, at: folder, to: &storage, exclusions: exclusions) {
            folders[added] = index
        }
    }

    private func forget(_ removedFolders: [Int32]) {
        for index in removedFolders {
            folders.removeValue(forKey: storage.path(Int(index)))
        }
    }

    private func nearestIndexedAncestor(of path: String) -> String? {
        var current = path
        while current != "/", !current.isEmpty {
            current = (current as NSString).deletingLastPathComponent
            if folders[current] != nil { return current }
        }
        return nil
    }

    private func compact() {
        storage = storage.compacted()
        folders = storage.folderPaths()
    }

    // MARK: Usage

    func index(of path: String) -> Int32? {
        if let folder = folders[path] { return folder }
        let parentPath = (path as NSString).deletingLastPathComponent
        guard let parent = folders[parentPath] else { return nil }
        return storage.children(of: parent)[(path as NSString).lastPathComponent]
    }

    /// Recomputes every boost in one pass over the index.
    func refreshBoosts() {
        let now = Date()
        boostsRefreshed = now
        guard !usage.isEmpty else { return }
        storage.boost = [Float](repeating: 0, count: storage.count)
        var wanted: [Int32: [String: Float]] = [:]
        for (path, entry) in usage {
            if let folder = folders[path] {
                storage.boost[Int(folder)] = entry.score(now: now)
            } else if let parent = folders[(path as NSString).deletingLastPathComponent] {
                wanted[parent, default: [:]][(path as NSString).lastPathComponent] = entry.score(now: now)
            }
        }
        guard !wanted.isEmpty else { return }
        for i in 0..<storage.count where storage.isLive(i) {
            guard let names = wanted[storage.parent[i]], let score = names[storage.name(i)] else { continue }
            storage.boost[i] = score
        }
    }

    static func distinctRoots(_ roots: [String]) -> [String] {
        let resolved = roots.map(FolderWatcher.realPath)
        var result: [String] = []
        for root in resolved where !result.contains(root) {
            if resolved.contains(where: { $0 != root && FolderChange.isInside(root, $0) }) { continue }
            result.append(root)
        }
        return result
    }
}
