import Foundation

/// An in-memory index of file and folder names under a set of root folders.
///
/// ```swift
/// let index = (try? FileIndex.load(from: snapshotURL)) ?? FileIndex(roots: [NSHomeDirectory()])
/// let count = await index.count, complete = await index.isComplete
/// if count == 0 || !complete { await index.build(savingTo: snapshotURL) }
/// await index.startWatching()
/// let matches = await index.search("gl rev", limit: 20)
/// ```
public actor FileIndex {
    public nonisolated let roots: [String]
    public nonisolated let exclusions: IndexExclusions
    /// Which folders a build walks first and last.
    public nonisolated let order: ScanOrder

    var storage = IndexStorage()
    var folders: [String: Int32] = [:]
    var usage: [String: Usage] = [:]
    var lastEventID: UInt64
    /// The FSEvents volume UUID of each root's disk, saved with the snapshot.
    var volumes: [String: String]
    var boostsRefreshed = Date.distantPast
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?
    private var watchLatency: TimeInterval = 0.5
    /// Where a rebuild the index starts by itself (after FSEvents dropped events
    /// for a whole root) saves to.
    private var autosave: URL?
    private var rebuildWanted = false
    /// The generation and usage at the last save, to tell whether a save is due.
    private var savedGeneration = 0
    private var usageChanged = false

    /// False while the index holds only part of its roots: during a first build,
    /// or after loading a snapshot saved before a build finished.
    public private(set) var isComplete: Bool
    public private(set) var isBuilding = false
    /// Folders the last build was not allowed to read (macOS privacy settings).
    public private(set) var unreadable: [String] = []
    /// When the index last matched the disk: the end of a build, the start of
    /// watching, or the last change applied.
    public private(set) var lastSync: Date?
    private var buildID = 0
    private var adoptedStep = 0
    private var partialSave: (url: URL, every: TimeInterval, last: Date)?
    private var partialWrite: Task<Void, Never>?
    /// Changes whenever entries are added, removed or renumbered.
    private var generation = 0 {
        didSet { generationContinuation.yield() }
    }
    /// One element whenever `changeCount` moves, the newest only, so a
    /// listener (the index service's change notices) waits without polling
    /// and a burst of changes reaches it as one.
    public nonisolated let generationChanges: AsyncStream<Void>
    private nonisolated let generationContinuation: AsyncStream<Void>.Continuation
    /// The last query and every entry it matched, so a query typed on from it
    /// only searches those. Callers that keep their own (one per client of the
    /// index service) pass it to `search(_:limit:scope:narrowing:)` instead.
    private var lastNarrowing: SearchNarrowing?
    /// The entries below the last scope searched.
    private var scopeCache: (key: [String], generation: Int, members: [Int32])?

    /// Roots are resolved to real paths, and a root inside another root is dropped.
    public init(roots: [String], exclusions: IndexExclusions = .standard, order: ScanOrder = .none) {
        self.roots = FileIndex.distinctRoots(roots)
        self.exclusions = exclusions
        self.order = order
        self.lastEventID = FolderWatcher.currentEventID
        self.volumes = [:]
        self.isComplete = false
        let made = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        generationChanges = made.stream
        generationContinuation = made.continuation
    }

    init(
        roots: [String], exclusions: IndexExclusions, order: ScanOrder = .none, storage: IndexStorage,
        usage: [String: Usage] = [:], lastEventID: UInt64, complete: Bool = true, volumes: [String: String] = [:]
    ) {
        self.roots = roots
        self.exclusions = exclusions
        self.order = order
        self.storage = storage
        self.folders = storage.folderPaths()
        self.usage = usage
        self.lastEventID = lastEventID
        self.volumes = volumes
        self.isComplete = complete
        let made = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        generationChanges = made.stream
        generationContinuation = made.continuation
    }

    deinit {
        watchTask?.cancel()
        generationContinuation.finish()
    }

    /// Files and folders in the index.
    public var count: Int { storage.liveCount }

    /// Scans every root from scratch. What has been walked so far can be searched
    /// while the walk goes on. With `snapshot`, the index is saved there every
    /// `every` seconds during the walk (marked as unfinished) and once at the end,
    /// so a crash or a forced quit keeps the work done.
    ///
    /// With `publishPartial` false (a periodic sweep of an index that is already
    /// complete), the current index is searched until the new walk is done. When
    /// the index is being watched, the watcher starts again from the event the walk
    /// began at, so a change made during the walk to a folder already walked is
    /// applied again rather than lost.
    public func build(
        savingTo snapshot: URL? = nil, every: TimeInterval = 30,
        priority: TaskPriority = .utility, publishPartial: Bool = true
    ) async {
        let roots = self.roots
        let exclusions = self.exclusions
        let order = self.order
        let started = FolderWatcher.currentEventID
        let startedVolumes = FolderWatcher.volumeUUIDs(for: roots)
        buildID += 1
        let id = buildID
        adoptedStep = 0
        isBuilding = true
        rebuildWanted = false
        partialSave = publishPartial ? snapshot.map { (url: $0, every: every, last: Date()) } : nil
        // A background walk (the weekly sweep) also reads the disk at the
        // throttled I/O tier, so it never slows the apps in front.
        let throttled = priority == .background
        let built = await Task.detached(priority: priority) {
            ThrottledIO.run(throttled) {
                FolderScanner.build(roots: roots, exclusions: exclusions, order: order, interval: publishPartial ? 0.25 : .infinity) { partial in
                    Task { await self.adopt(partial, build: id) }
                }
            }
        }.value
        guard id == buildID else { return }
        storage = built.storage
        folders = built.folders
        unreadable = built.unreadable
        generation += 1
        lastEventID = started
        volumes = startedVolumes
        isComplete = true
        isBuilding = false
        lastSync = Date()
        partialSave = nil
        refreshBoosts()
        if watcher != nil {
            stopWatching()
            startWatching(latency: watchLatency)
        }
        // A save from part way through must not land on top of the finished one.
        await partialWrite?.value
        partialWrite = nil
        guard id == buildID else { return }
        if let snapshot { try? save(to: snapshot) }
        if rebuildWanted {
            rebuildWanted = false
            rebuildInBackground()
        }
    }

    /// Starts a full walk without waiting for it; the current index stays
    /// searchable meanwhile. A walk already under way runs again once it ends.
    public func rebuildInBackground(priority: TaskPriority = .utility) {
        guard !isBuilding else {
            rebuildWanted = true
            return
        }
        let snapshot = autosave
        let partial = storage.liveCount == 0
        Task { await self.build(savingTo: snapshot, every: 60, priority: priority, publishPartial: partial) }
    }

    /// Where `rebuildInBackground()` and the rebuilds the watcher asks for save.
    public func setAutosave(_ url: URL?) {
        autosave = url
    }

    /// Takes part of a build in progress, unless it holds fewer entries than the
    /// index already has (a partial snapshot loaded at launch, say).
    func adopt(_ partial: BuiltIndex, build id: Int) {
        guard isBuilding, id == buildID, partial.step > adoptedStep else { return }
        adoptedStep = partial.step
        unreadable = partial.unreadable
        guard partial.storage.count >= storage.liveCount else { return }
        storage = partial.storage
        folders = partial.folders
        generation += 1
        if let plan = partialSave, Date().timeIntervalSince(plan.last) >= plan.every {
            partialSave?.last = Date()
            let snapshot = IndexSnapshot(roots: roots, storage: storage, usage: usage, lastEventID: lastEventID, complete: false)
            let url = plan.url
            let previous = partialWrite
            partialWrite = Task.detached(priority: .background) {
                await previous?.value
                try? FileIndex.write(snapshot, to: url)
            }
        }
    }

    /// The best `limit` matches, best first.
    public func search(_ text: String, limit: Int = 50) async -> [IndexMatch] {
        let result = await search(text, limit: limit, scope: nil, narrowing: lastNarrowing)
        lastNarrowing = result.narrowing
        return result.matches
    }

    /// The best `limit` matches below the `scope` folders (nil or empty: the
    /// whole index), best first. Pass back the narrowing the last call returned
    /// to the same caller: when the query extends that one, only what it matched
    /// is searched again.
    public func search(
        _ text: String, limit: Int, scope: [String]?, narrowing: SearchNarrowing?
    ) async -> (matches: [IndexMatch], narrowing: SearchNarrowing?) {
        guard limit > 0, let query = SearchQuery(text), storage.count > 0 else { return ([], narrowing) }
        if Date().timeIntervalSince(boostsRefreshed) > 3_600 { refreshBoosts() }
        let storage = self.storage
        let generation = self.generation
        let within: [Int32]?
        let scopeKey: [String]
        switch resolve(scope) {
        case .whole:
            within = nil
            scopeKey = []
        case .nothing:
            return ([], narrowing)
        case .folders(let key, let members):
            within = members
            scopeKey = key
        }
        var narrowed: [Int32]? = nil
        if let last = narrowing, last.generation == generation, last.scope == scopeKey, query.narrows(last.query) {
            narrowed = last.matched
        }
        let candidates = narrowed ?? within
        let count = candidates?.count ?? storage.count
        let chunks = max(1, min(ProcessInfo.processInfo.activeProcessorCount * 2, count / 8_192 + 1))
        let size = (count + chunks - 1) / chunks
        let found = await withTaskGroup(of: ScanResult.self) { group in
            for chunk in 0..<chunks {
                let range = (chunk * size)..<min(count, (chunk + 1) * size)
                if range.isEmpty { continue }
                group.addTask { IndexSearch.scan(storage, query, range, candidates: candidates, limit: limit) }
            }
            var all = ScanResult()
            for await part in group {
                all.hits += part.hits
                all.matched += part.matched
            }
            return all
        }
        let next = SearchNarrowing(query: query, generation: generation, scope: scopeKey, matched: found.matched)
        var hits = found.hits
        hits.sort(by: Hit.ranksBefore)
        let matches: [IndexMatch] = hits.prefix(limit).map { hit in
            let i = Int(hit.index)
            return IndexMatch(
                path: storage.path(i),
                name: storage.name(i),
                isFolder: storage.isFolder(i),
                tier: hit.tier,
                highlights: IndexSearch.highlights(storage, i, query)
            )
        }
        return (matches, next)
    }

    private enum Scope {
        case whole
        case nothing
        case folders(key: [String], members: [Int32])
    }

    /// The entries below the scope folders. A folder that holds a root means the
    /// whole index; a folder the index does not know adds nothing.
    private func resolve(_ scope: [String]?) -> Scope {
        guard let scope, !scope.isEmpty else { return .whole }
        var seeds = Set<Int32>()
        var key: [String] = []
        for folder in scope {
            let real = FolderWatcher.realPath(folder)
            if roots.contains(where: { FolderChange.isInside($0, real) }) { return .whole }
            if let index = folders[real] {
                seeds.insert(index)
                key.append(real)
            }
        }
        guard !seeds.isEmpty else { return .nothing }
        key.sort()
        if let cached = scopeCache, cached.key == key, cached.generation == generation {
            return .folders(key: key, members: cached.members)
        }
        // A parent always comes before its children, so one pass marks everything below.
        var inside = [Bool](repeating: false, count: storage.count)
        var members: [Int32] = []
        for i in 0..<storage.count {
            let parent = storage.parent[i]
            if seeds.contains(Int32(i)) {
                inside[i] = true
            } else if parent >= 0, inside[Int(parent)] {
                inside[i] = true
                if storage.isLive(i) { members.append(Int32(i)) }
            }
        }
        scopeCache = (key, generation, members)
        return .folders(key: key, members: members)
    }

    /// How many files and folders, how fresh, and what could not be read.
    public func status() -> IndexStatus {
        IndexStatus(
            files: storage.liveCount, lastSync: lastSync, building: isBuilding,
            unreadable: unreadable, complete: isComplete, roots: roots
        )
    }

    /// Changes whenever entries are added, removed or renumbered.
    public var changeCount: Int { generation }

    /// Whether the index or its usage changed since it was last saved or loaded.
    public var hasUnsavedChanges: Bool { generation != savedGeneration || usageChanged }

    /// The FSEvents volume UUIDs saved with the index, by root.
    public var volumeUUIDs: [String: String] { volumes }

    /// The event the index has caught up to, saved with it.
    public var eventID: UInt64 { lastEventID }

    /// Records the volumes the index now belongs to, after a startup check found
    /// its history still good.
    public func setVolumes(_ volumes: [String: String]) {
        self.volumes = volumes
    }

    /// Removes these paths and everything below them: the folders a snapshot
    /// from a wider scope (Nexus indexed all of ~/Library) holds but this index
    /// leaves out.
    public func prune(_ paths: Set<String>) {
        var removed = false
        for path in paths {
            guard let entry = index(of: FolderChange.normalize(path)) else { continue }
            forget(storage.remove(entry))
            removed = true
        }
        if removed { generation += 1 }
    }

    /// The most paths whose opens are remembered; the least recently opened go first.
    public static let maxUsage = 5_000
    /// Opens older than this no longer count (Usage scores them at nothing past 30 days).
    public static let usageLifetime: TimeInterval = 180 * 86_400

    /// Records an open, which lifts the path above equal matches from then on.
    /// Only paths in the index count (a client may send any path), and only
    /// the `maxUsage` most recently opened are kept.
    public func noteOpened(_ path: String, at date: Date = Date()) {
        let path = FolderChange.normalize(path)
        guard let index = index(of: path) else { return }
        var entry = usage[path] ?? Usage(count: 0, last: date)
        entry.count += 1
        entry.last = max(entry.last, date)
        usage[path] = entry
        usageChanged = true
        storage.boost[Int(index)] = entry.score(now: Date())
        if usage.count > Self.maxUsage { trimUsage(now: date) }
    }

    /// Drops opens past their lifetime, then the least recent beyond `maxUsage`.
    func trimUsage(now: Date = Date()) {
        let before = usage.count
        usage = usage.filter { now.timeIntervalSince($0.value.last) < Self.usageLifetime }
        if usage.count > Self.maxUsage {
            let oldest = usage.sorted { $0.value.last < $1.value.last }.prefix(usage.count - Self.maxUsage)
            for (path, _) in oldest { usage[path] = nil }
        }
        if usage.count != before { usageChanged = true }
    }

    /// The number of paths whose opens are remembered (for tests and status).
    public var usageCount: Int { usage.count }

    /// Rescans the changed folders: only their direct contents, or everything below
    /// for a recursive change. New folders are scanned in full.
    /// Changes inside folders the index leaves out (the index's own snapshot in
    /// ~/Library/Application Support, say) are skipped, and the index counts as
    /// changed only when an entry came or went, so a save does not set off
    /// another save and a narrowing survives events that change nothing.
    ///
    /// Changes inside an excluded tree (node_modules, .git, DerivedData, an app
    /// bundle, ~/Library outside CloudStorage) are dropped before any work, and
    /// a folder the index does not know is answered by rescanning its nearest
    /// indexed ancestor, once per batch however many changes lead there.
    public func apply(_ changes: [FolderChange]) {
        let before = (storage.count, storage.removedCount)
        var ancestors = Set<String>()
        var rescanned = Set<String>()
        for change in FolderChange.coalesce(changes) where !isExcluded(change.path) {
            if folders[change.path] != nil {
                rescan(change.path, recursive: change.recursive)
                rescanned.insert(change.path)
            } else if let parent = nearestIndexedAncestor(of: change.path) {
                ancestors.insert(parent)
            }
        }
        for parent in ancestors.sorted() where !rescanned.contains(parent) && folders[parent] != nil {
            rescan(parent, recursive: false)
        }
        if !changes.isEmpty { lastSync = Date() }
        if (storage.count, storage.removedCount) != before { generation += 1 }
        if storage.removedCount > 10_000, storage.removedCount * 4 > storage.count { compact() }
    }

    /// What the watcher reports. A whole root to rescan (FSEvents dropped events,
    /// or the root itself changed) is walked in the background instead, so
    /// searches are not held up while the home folder is read again. The
    /// batch's event ID is stored only once its changes are applied, so a save
    /// (or a quit) never records events still waiting in the stream.
    func applyWatched(_ batch: WatchBatch) {
        var rest: [FolderChange] = []
        var wholeRoot = false
        for change in batch.changes {
            if change.recursive, roots.contains(change.path), storage.liveCount > 0 {
                wholeRoot = true
            } else {
                rest.append(change)
            }
        }
        apply(rest)
        // A whole-root walk starts from the event it begins at (see `build`).
        lastEventID = max(lastEventID, batch.eventID)
        if wholeRoot { rebuildInBackground() }
    }

    /// Follows changes with FSEvents, replaying what changed since the last build or snapshot.
    public func startWatching(latency: TimeInterval = 0.5) {
        guard watcher == nil else { return }
        watchLatency = latency
        let watcher = FolderWatcher(paths: roots, since: lastEventID, latency: latency, tagged: true)
        guard watcher.start() else { return }
        self.watcher = watcher
        if lastSync == nil { lastSync = Date() }
        let batches = watcher.batches
        watchTask = Task { [weak self] in
            for await batch in batches {
                await self?.applyWatched(batch)
            }
        }
    }

    /// Whether FSEvents is being followed.
    public var isWatching: Bool { watcher != nil }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        watcher?.stop()
        watcher = nil
    }

    /// Writes the index, usage and the last event applied, for an instant start
    /// next time: events seen but not yet applied are replayed then.
    public func save(to url: URL) throws {
        if storage.removedCount > 0 { compact() }
        if usage.count > Self.maxUsage { trimUsage() }
        let snapshot = IndexSnapshot(
            roots: roots, storage: storage, usage: usage, lastEventID: lastEventID,
            complete: isComplete, volumes: volumes
        )
        try FileIndex.write(snapshot, to: url)
        savedGeneration = generation
        usageChanged = false
    }

    static func write(_ snapshot: IndexSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try snapshot.encoded().write(to: url, options: .atomic)
    }

    /// Reads a saved index. Call `startWatching()` afterwards to catch up on changes,
    /// and `build()` when `isComplete` is false.
    public static func load(from url: URL, exclusions: IndexExclusions = .standard, order: ScanOrder = .none) throws -> FileIndex {
        let snapshot = try IndexSnapshot(decoding: Data(contentsOf: url))
        let index = FileIndex(
            roots: snapshot.roots, exclusions: exclusions, order: order, storage: snapshot.storage,
            usage: snapshot.usage, lastEventID: snapshot.lastEventID, complete: snapshot.complete,
            volumes: snapshot.volumes
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

    /// Whether a changed path lies in a tree the index leaves out: below an
    /// excluded path or rule, or with a name on the way down from its root
    /// that is skipped (node_modules, .git) or a package (Xcode.app).
    func isExcluded(_ path: String) -> Bool {
        if exclusions.excludes(path) { return true }
        guard let root = roots.first(where: { FolderChange.isInside(path, $0) }), path != root else { return false }
        let below = path.dropFirst(root.hasSuffix("/") ? root.count : root.count + 1)
        for name in below.split(separator: "/") {
            let name = String(name)
            if exclusions.skips(name) || exclusions.isPackage(name) { return true }
        }
        return false
    }

    /// Removes what the exclusions leave out from an index loaded from a
    /// snapshot (Nexus's, which indexed all of ~/Library, or this index's own
    /// from before a folder appeared in ~/Library). Returns the entries removed.
    @discardableResult
    public func pruneExcluded() -> Int {
        let before = storage.removedCount
        var gone: [String] = []
        for (path, _) in folders where exclusions.excludes(path) {
            let parent = (path as NSString).deletingLastPathComponent
            if !exclusions.excludes(parent) { gone.append(path) }
        }
        for path in gone {
            guard let entry = folders[path] else { continue }
            forget(storage.remove(entry))
        }
        // Files right inside a folder that keeps only some of its children.
        for parent in exclusions.keptOnly.keys {
            guard let folder = folders[parent] else { continue }
            for (name, child) in storage.children(of: folder) where exclusions.skips(path: IndexStorage.join(parent, name)) {
                forget(storage.remove(child))
            }
        }
        let removed = storage.removedCount - before
        if removed > 0 { generation += 1 }
        return removed
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
        generation += 1
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
