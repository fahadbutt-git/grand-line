import Foundation
import IndexKit
import os

/// The shared name index the Grand Line Index agent keeps: loaded from its
/// snapshot (or adopted from Sight's or Nexus's on the first start), caught up
/// with FSEvents from the stored event, walked again only when FSEvents history
/// cannot be trusted, saved every few minutes and on quit, and swept once a week
/// at background priority.
public final class IndexServiceCore: @unchecked Sendable {
    public let locations: IndexLocations
    /// How often a changed index is saved.
    public let saveEvery: TimeInterval
    /// FSEvents latency: how long after a change it reaches the index.
    public let latency: TimeInterval

    private let log: Logger
    private let loader: Task<FileIndex, Never>
    private let lock = NSLock()
    private var sessions: [WeakSession] = []
    private var maintenance: [Task<Void, Never>] = []

    public init(locations: IndexLocations = IndexLocations(), saveEvery: TimeInterval = 300, latency: TimeInterval = 0.3) {
        self.locations = locations
        self.saveEvery = saveEvery
        self.latency = latency
        let log = Logger(subsystem: "com.grandline.index", category: "index")
        self.log = log
        loader = Task.detached(priority: .userInitiated) {
            await IndexServiceCore.open(locations, latency: latency, log: log)
        }
    }

    /// The index, once its snapshot is loaded (at once for later callers).
    public func index() async -> FileIndex {
        await loader.value
    }

    /// Starts the periodic save, the weekly sweep check and change notices.
    ///
    /// Nothing here wakes the Mac while the index is unchanged: the save check
    /// sleeps `saveEvery` with a fifth of it as tolerance (macOS folds the
    /// wake-up in with others), and change notices wait on the index's own
    /// change stream instead of asking it every second. While files keep
    /// changing, notices go out at most once a second.
    public func start() {
        // The index's change stream has one listener: a second start is a no-op.
        lock.lock()
        let running = !maintenance.isEmpty
        lock.unlock()
        guard !running else { return }
        let save = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.saveEvery else { return }
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(Self.tolerance(for: interval)), clock: .continuous)
                await self?.maintain()
            }
        }
        let notices = Task.detached(priority: .utility) { [weak self] in
            guard let changes = await self?.index().generationChanges else { return }
            for await _ in changes {
                guard let core = self else { return }
                core.broadcast(await core.index().count)
                try? await Task.sleep(nanoseconds: UInt64(Self.noticeGap * 1_000_000_000))
            }
        }
        lock.lock()
        maintenance = [save, notices]
        lock.unlock()
    }

    /// The shortest time between two change notices.
    static let noticeGap: TimeInterval = 1

    /// How late a periodic wake-up may come: a fifth of its interval, so
    /// macOS can fold it in with other wake-ups.
    static func tolerance(for interval: TimeInterval) -> TimeInterval {
        max(1, interval * 0.2)
    }

    public func stop() {
        lock.lock()
        let tasks = maintenance
        maintenance = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    // MARK: Opening

    static func open(_ locations: IndexLocations, latency: TimeInterval, log: Logger) async -> FileIndex {
        let exclusions = IndexExclusions.home(locations.home)
        let order = ScanOrder.home(locations.home)
        let index: FileIndex
        // The read blocks on the disk: off the concurrency pool, which the
        // sessions' searches and hellos need meanwhile.
        let adopted: Adopted? = await BlockingWork.run(qos: .userInitiated) {
            SnapshotAdoption.load(locations, exclusions: exclusions, order: order).map { Adopted(index: $0.index, origin: $0.origin) }
        }
        if let found = adopted {
            index = found.index
            if found.origin != .own {
                // Nexus indexed all of ~/Library; this index leaves most of it out.
                await index.prune(exclusions.paths)
                do {
                    try await index.save(to: locations.snapshot)
                    log.info("Adopted the \(found.origin.rawValue, privacy: .public) snapshot")
                } catch {
                    log.error("Could not save the adopted snapshot: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else {
            index = FileIndex(roots: locations.roots, exclusions: exclusions, order: order)
        }
        await index.setAutosave(locations.snapshot)
        let roots = index.roots
        let current = FolderWatcher.volumeUUIDs(for: roots)
        let decision = IndexRecovery.startup(
            count: await index.count, complete: await index.isComplete,
            storedEventID: await index.eventID, currentEventID: FolderWatcher.currentEventID,
            roots: roots, storedVolumes: await index.volumeUUIDs, currentVolumes: current
        )
        let snapshot = locations.snapshot
        switch decision {
        case .resume:
            await index.setVolumes(current)
            await index.startWatching(latency: latency)
        case .build:
            log.info("No snapshot: walking the home folder")
            Task.detached(priority: .utility) {
                await index.build(savingTo: snapshot, every: 30)
                await index.startWatching(latency: latency)
            }
        case .rebuild(let reason):
            log.info("Walking again: \(String(describing: reason), privacy: .public)")
            let partial = reason == .incomplete
            Task.detached(priority: .utility) {
                await index.build(savingTo: snapshot, every: 60, publishPartial: partial)
                await index.startWatching(latency: latency)
            }
        }
        return index
    }

    // MARK: Upkeep

    /// Saves a changed index and starts the weekly sweep when it is due.
    public func maintain(now: Date = Date()) async {
        let index = await index()
        let building = await index.isBuilding
        if !building, await index.hasUnsavedChanges {
            do { try await index.save(to: locations.snapshot) } catch {
                log.error("Could not save the index: \(error.localizedDescription, privacy: .public)")
            }
        }
        var state = ServiceState.read(locations.state)
        if state.lastSweep == nil {
            state.lastSweep = now
            state.write(locations.state)
        } else if !building, IndexRecovery.sweepDue(last: state.lastSweep, now: now) {
            state.lastSweep = now
            state.write(locations.state)
            let snapshot = locations.snapshot
            log.info("Weekly sweep")
            Task.detached(priority: .background) {
                await index.build(savingTo: snapshot, every: 300, priority: .background, publishPartial: false)
            }
        }
    }

    /// Saves now, for quitting.
    public func saveNow() async {
        let index = await index()
        guard await index.hasUnsavedChanges || !FileManager.default.fileExists(atPath: locations.snapshot.path) else { return }
        try? await index.save(to: locations.snapshot)
    }

    /// For SIGTERM from launchd: saves, then exits. Waits at most 20 s
    /// (the agent's ExitTimeOut is 30).
    public func saveAndExit() -> Never {
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await self.saveNow()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        exit(0)
    }

    // MARK: Answers

    public func status() async -> IndexStatus {
        var status = await index().status()
        status.source = .service
        return status
    }

    public func rebuild() async {
        await index().rebuildInBackground()
    }

    /// Whether a client's home folder is the one indexed here.
    public func serves(home: String) -> Bool {
        locations.roots == [FolderWatcher.realPath(home)]
    }

    // MARK: Change notices

    func register(_ session: IndexSession) {
        lock.lock()
        sessions.removeAll { $0.session == nil }
        sessions.append(WeakSession(session: session))
        lock.unlock()
    }

    private func broadcast(_ files: Int) {
        lock.lock()
        let live = sessions.compactMap(\.session)
        lock.unlock()
        for session in live { session.notifyChanged(files) }
    }
}

private struct WeakSession {
    weak var session: IndexSession?
}

private struct Adopted: Sendable {
    let index: FileIndex
    let origin: SnapshotAdoption.Origin
}

/// What the service remembers between runs besides the index.
struct ServiceState: Codable, Equatable {
    var lastSweep: Date?

    static func read(_ url: URL) -> ServiceState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ServiceState.self, from: data) else { return ServiceState() }
        return state
    }

    func write(_ url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
