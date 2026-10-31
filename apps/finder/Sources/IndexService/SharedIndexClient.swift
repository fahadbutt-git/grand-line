import Foundation
import IndexKit

/// How Nexus and Sight search file names: they ask the Grand Line Index
/// service, which keeps one index of the home folder for both. When the service
/// cannot be reached, the client starts it and meanwhile answers from its own
/// copy, read from the service's snapshot (never written), so a search never
/// waits on the service or comes back empty. If the service stays out of reach,
/// that copy follows FSEvents too (and is walked, in memory, when there is no
/// snapshot at all).
public final class SharedIndexClient: IndexStatusProviding, @unchecked Sendable {
    public typealias Starter = @Sendable () -> Void

    public let home: String
    /// nil: no service, the client's own copy only (a journey without a service).
    public let serviceName: String?
    /// How long a search waits for the service before answering from the copy.
    public let replyTimeout: TimeInterval
    /// How long the service may be out of reach before the copy follows FSEvents.
    public let liveAfter: TimeInterval

    private let starter: Starter
    private let local: LocalIndex
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var state = State.unknown
    private var lastStart = Date.distantPast
    private var lastLocalUse = Date.distantPast
    private var changeHandler: (@Sendable (Int) -> Void)?

    enum State: Equatable {
        /// Not asked yet, or a new connection is being tried.
        case unknown
        case up
        /// Out of reach since this time; tried again after `retryAfter`.
        case down(since: Date, retried: Date)
        /// It indexes another home folder; never asked again.
        case refused
    }

    static let retryAfter: TimeInterval = 2
    static let startEvery: TimeInterval = 60

    public init(
        home: String = NSHomeDirectory(),
        serviceName: String? = IndexServiceName.forClient(),
        replyTimeout: TimeInterval = 0.5,
        liveAfter: TimeInterval = 5,
        starter: Starter? = nil
    ) {
        self.home = home
        self.serviceName = serviceName
        self.replyTimeout = replyTimeout
        self.liveAfter = liveAfter
        self.starter = starter ?? SharedIndexClient.defaultStarter()
        self.local = LocalIndex(locations: IndexLocations(home: home))
    }

    /// Opens `open -g -j -b com.grandline.index`, which registers the agent
    /// with launchd (or finds it registered) and exits. Not during journeys.
    public static func defaultStarter(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Starter {
        if environment["GRAND_LINE_JOURNEY"] == "1" { return {} }
        return {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-g", "-j", "-b", IndexServiceName.bundleID]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }

    /// Connects in the background. Without a service, the copy is loaded and
    /// followed at once.
    public func start() {
        guard serviceName != nil else {
            local.goLive()
            return
        }
        Task.detached(priority: .userInitiated) { [self] in
            _ = self.shouldAskService()
        }
    }

    public func stop() {
        lock.lock()
        let old = connection
        connection = nil
        lock.unlock()
        old?.invalidate()
    }

    /// Called with the number of files whenever the index changes, about once
    /// a second at most, while the service is reachable.
    public func onChange(_ handler: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    // MARK: Asking

    /// The best `limit` name matches below `scope` (nil: the whole index).
    public func search(_ text: String, limit: Int, scope: [String]? = nil) async -> [IndexMatch] {
        if shouldAskService() {
            let data: Data? = await call(timeout: replyTimeout) { service, done in
                service.search(text, limit: limit, scope: scope ?? [], reply: done)
            }
            if let data, let matches = MatchCodec.decode(data) {
                markUp()
                return matches
            }
            markDown()
        }
        noteLocalUse()
        return await local.search(text, limit: limit, scope: scope)
    }

    public func noteOpened(_ path: String) {
        if isUp, let connection = currentConnection(),
           let service = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? IndexServiceXPC {
            service.noteOpened(path)
        } else {
            local.noteOpened(path)
        }
    }

    public func status() async -> IndexStatus {
        if shouldAskService() {
            let data: Data? = await call(timeout: 2) { service, done in service.status(reply: done) }
            if let data, let status = IndexStatus(encoded: data) {
                markUp()
                return status
            }
            markDown()
        }
        return await local.status()
    }

    public func rebuild() async {
        if shouldAskService() {
            let done: Bool? = await call(timeout: 5) { service, reply in service.rebuild { reply(true) } }
            if done == true { return }
            markDown()
        }
        await local.rebuild()
    }

    /// Folders macOS would not let the index read.
    public func unreadable() async -> [String] {
        await status().unreadable
    }

    // MARK: The connection

    var currentState: State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    private var isUp: Bool { currentState == .up }

    private func currentConnection() -> NSXPCConnection? {
        lock.lock()
        defer { lock.unlock() }
        return connection
    }

    /// Whether to try the service for this request; makes a new connection
    /// when there is none, or when the last one failed long enough ago. Only
    /// one caller makes it: the check and the new connection are under the lock.
    func shouldAskService() -> Bool {
        guard serviceName != nil else { return false }
        let now = Date()
        lock.lock()
        var fresh: NSXPCConnection?
        var old: NSXPCConnection?
        switch state {
        case .refused:
            lock.unlock()
            return false
        case .up, .unknown:
            if connection == nil {
                fresh = newConnection()
                connection = fresh
            }
        case .down(let since, let retried):
            guard now.timeIntervalSince(retried) >= Self.retryAfter else {
                lock.unlock()
                return false
            }
            state = .down(since: since, retried: now)
            old = connection
            fresh = newConnection()
            connection = fresh
        }
        fresh?.resume()
        lock.unlock()
        old?.invalidate()
        if let fresh {
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                if await self.greet(fresh) == false, self.currentConnection() === fresh { self.markDown() }
            }
        }
        return true
    }

    /// A configured connection, not yet resumed. Called under the lock; it
    /// only sets properties, and the handlers run later on XPC's own queue.
    private func newConnection() -> NSXPCConnection? {
        guard let serviceName else { return nil }
        let connection = NSXPCConnection(machServiceName: serviceName, options: [])
        connection.remoteObjectInterface = IndexXPC.serviceInterface()
        connection.exportedInterface = IndexXPC.eventsInterface()
        connection.exportedObject = EventReceiver(client: self)
        if let requirement = CodeSigning.requirement(allowing: [IndexServiceName.bundleID], signer: CodeSigning.own) {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            self?.dropped(connection)
        }
        connection.interruptionHandler = { [weak self, weak connection] in
            // The agent quit or crashed; launchd starts it again on the next message.
            guard let self, let connection, self.currentConnection() === connection else { return }
            self.markDown()
        }
        return connection
    }

    private func greet(_ connection: NSXPCConnection) async -> Bool {
        let home = self.home
        let reply: (Bool, Data)? = await call(on: connection, timeout: 3) { service, done in
            service.hello(home) { accepted, status in done((accepted, status)) }
        }
        guard let reply else { return false }
        if !reply.0 {
            lock.lock()
            state = .refused
            self.connection = nil
            lock.unlock()
            connection.invalidate()
            local.goLive()
            return true
        }
        markUp()
        (connection.remoteObjectProxyWithErrorHandler { _ in } as? IndexServiceXPC)?.subscribe()
        return true
    }

    private func dropped(_ dead: NSXPCConnection?) {
        lock.lock()
        let current = dead != nil && connection === dead
        if current { connection = nil }
        lock.unlock()
        if current, currentState != .refused { markDown() }
    }

    func markUp() {
        lock.lock()
        if state != .refused { state = .up }
        let releaseCopy = Date().timeIntervalSince(lastLocalUse) > 60
        lock.unlock()
        if releaseCopy { local.releaseIfIdle() }
    }

    func markDown() {
        let now = Date()
        lock.lock()
        var firstFailure = false
        switch state {
        case .refused, .down:
            break
        case .up, .unknown:
            state = .down(since: now, retried: now)
            firstFailure = true
        }
        let start = now.timeIntervalSince(lastStart) >= Self.startEvery
        if start { lastStart = now }
        lock.unlock()
        if start { starter() }
        if firstFailure {
            let wait = liveAfter
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                if case .down = self.currentState { self.local.goLive() }
            }
        }
    }

    private func noteLocalUse() {
        lock.lock()
        lastLocalUse = Date()
        lock.unlock()
    }

    fileprivate func receivedChange(_ files: Int) {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?(files)
    }

    private func call<T>(timeout: TimeInterval, _ body: @escaping (IndexServiceXPC, @escaping (T) -> Void) -> Void) async -> T? {
        guard let connection = currentConnection() else { return nil }
        return await call(on: connection, timeout: timeout, body)
    }

    private func call<T>(
        on connection: NSXPCConnection, timeout: TimeInterval,
        _ body: @escaping (IndexServiceXPC, @escaping (T) -> Void) -> Void
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) }
            guard let service = proxy as? IndexServiceXPC else {
                once.resume(nil)
                return
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { once.resume(nil) }
            body(service) { value in once.resume(value) }
        }
    }
}

/// Receives the service's change notices on the client's connection.
private final class EventReceiver: NSObject, IndexEventsXPC {
    weak var client: SharedIndexClient?

    init(client: SharedIndexClient) {
        self.client = client
    }

    func indexChanged(_ files: Int) {
        client?.receivedChange(files)
    }
}

/// The client's own copy of the index, for when the service is out of reach:
/// loaded from the service's snapshot (or Sight's or Nexus's from before the
/// service) on first use, never saved.
final class LocalIndex: @unchecked Sendable {
    let locations: IndexLocations
    private let lock = NSLock()
    private var loading: Task<FileIndex, Never>?
    private var live = false
    private var narrowing: SearchNarrowing?

    init(locations: IndexLocations) {
        self.locations = locations
    }

    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loading != nil
    }

    var isLive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return live
    }

    func index() async -> FileIndex {
        lock.lock()
        if let loading {
            lock.unlock()
            return await loading.value
        }
        let locations = self.locations
        let task = Task.detached(priority: .userInitiated) { await LocalIndex.open(locations) }
        loading = task
        lock.unlock()
        return await task.value
    }

    static func open(_ locations: IndexLocations) async -> FileIndex {
        let exclusions = IndexExclusions.home(locations.home)
        let order = ScanOrder.home(locations.home)
        guard let found = SnapshotAdoption.load(locations, exclusions: exclusions, order: order) else {
            return FileIndex(roots: locations.roots, exclusions: exclusions, order: order)
        }
        if found.origin != .own { await found.index.prune(exclusions.paths) }
        return found.index
    }

    func search(_ text: String, limit: Int, scope: [String]?) async -> [IndexMatch] {
        let index = await index()
        lock.lock()
        let previous = narrowing
        lock.unlock()
        let found = await index.search(text, limit: limit, scope: scope, narrowing: previous)
        lock.lock()
        narrowing = found.narrowing
        lock.unlock()
        return found.matches
    }

    func status() async -> IndexStatus {
        var status = await index().status()
        status.source = .inApp
        return status
    }

    func noteOpened(_ path: String) {
        guard isLoaded else { return }
        Task { await self.index().noteOpened(path) }
    }

    /// Follows FSEvents from the snapshot's event, and walks the home folder in
    /// memory when there was no snapshot.
    func goLive() {
        lock.lock()
        let first = !live
        live = true
        lock.unlock()
        guard first else { return }
        Task.detached(priority: .utility) {
            let index = await self.index()
            let count = await index.count
            let complete = await index.isComplete
            if count == 0 || !complete { await index.build(savingTo: nil) }
            await index.startWatching()
        }
    }

    func rebuild() async {
        goLive()
        await index().rebuildInBackground()
    }

    /// Lets the copy go once the service has answered for a while.
    func releaseIfIdle() {
        lock.lock()
        guard let loaded = loading else {
            lock.unlock()
            return
        }
        let wasLive = live
        loading = nil
        live = false
        narrowing = nil
        lock.unlock()
        if wasLive {
            Task.detached(priority: .utility) { await loaded.value.stopWatching() }
        }
    }
}
