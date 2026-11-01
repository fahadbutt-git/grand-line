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
    private var lateHandler: (@Sendable () -> Void)?
    /// A release check of the copy is waiting to run.
    private var releaseScheduled = false
    /// How long a search gives the service before the copy races it. The
    /// service is the one that knows about files made while an app was closed.
    public let headStart: TimeInterval
    /// How long a search's answer from the service is still waited for once
    /// the copy has answered, to refine what is shown.
    static let lateAnswer: TimeInterval = 3

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
    /// How long the copy is kept after its last use once the service answers.
    static let copyRetention: TimeInterval = 60

    /// What to do with the client's own copy of the index.
    enum CopyRelease: Equatable {
        /// Not loaded, or still needed while the service is out of reach.
        case keep
        case now
        /// Look again after this long.
        case after(TimeInterval)
    }

    /// The copy goes once the service has answered and the copy has not been
    /// used for `retention` seconds, so an app does not hold a second index
    /// in memory for long after a slow start.
    static func copyRelease(up: Bool, loaded: Bool, lastLocalUse: Date, now: Date,
                            retention: TimeInterval = SharedIndexClient.copyRetention) -> CopyRelease {
        guard loaded, up else { return .keep }
        let idle = now.timeIntervalSince(lastLocalUse)
        return idle >= retention ? .now : .after(retention - idle)
    }

    public init(
        home: String = NSHomeDirectory(),
        serviceName: String? = IndexServiceName.forClient(),
        replyTimeout: TimeInterval = 0.5,
        liveAfter: TimeInterval = 5,
        headStart: TimeInterval = 0.15,
        starter: Starter? = nil
    ) {
        self.home = home
        self.serviceName = serviceName
        self.headStart = min(headStart, replyTimeout)
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

    /// Connects in the background, at once (an app calls it at launch, before
    /// its first search). Without a service, the copy is loaded and followed at
    /// once. When the service has not said hello within a second, the copy is
    /// loaded too, so a search racing a slow service has an answer ready.
    public func start() {
        guard serviceName != nil else {
            local.goLive()
            return
        }
        Task.detached(priority: .userInitiated) { [self] in
            _ = self.shouldAskService()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if self.currentState != .up, self.currentState != .refused {
                _ = await self.local.index()
                self.scheduleCopyRelease()
            }
        }
    }

    /// Keeps the connection open: reconnects when it was dropped (after the
    /// usual pause), so the next search finds it ready. Cheap; call it when a
    /// window opens and now and then.
    public func warm() {
        guard serviceName != nil else { return }
        _ = shouldAskService()
    }

    /// Called when the service answered a search after the copy already had:
    /// the app searches again to show the service's fuller answer.
    public func onLateAnswer(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        lateHandler = handler
        lock.unlock()
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
    ///
    /// The service gets a head start; after it, the copy races it and the
    /// first to answer is shown, so a slow connection (just after launch)
    /// never holds up a search. When the copy wins, the service's answer is
    /// still awaited: it marks the service up and calls `onLateAnswer`, so the
    /// app can search again and show what only the service knows. Only a
    /// failed connection, not a slow one, sends searches to the copy for a while.
    public func search(_ text: String, limit: Int, scope: [String]? = nil) async -> [IndexMatch] {
        guard shouldAskService() else {
            noteLocalUse()
            return await local.search(text, limit: limit, scope: scope)
        }
        let asked = Task { () -> Reply<Data> in
            await self.reply(timeout: Self.lateAnswer) { service, done in
                service.search(text, limit: limit, scope: scope ?? [], reply: done)
            }
        }
        let local = self.local
        let headStart = self.headStart
        let first: SearchRace = await withCheckedContinuation { (continuation: CheckedContinuation<SearchRace?, Never>) in
            let once = Once(continuation)
            Task { once.resume(.service(await asked.value)) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(headStart * 1_000_000_000))
                guard !once.isDone else { return }
                once.resume(.copy(await local.search(text, limit: limit, scope: scope)))
            }
        } ?? .copy([])
        switch first {
        case .service(.value(let data)):
            if let matches = MatchCodec.decode(data) {
                markUp()
                return matches
            }
            markDown()
        case .service(.failed), .service(.timedOut):
            markDown()
        case .copy(let matches):
            noteLocalUse()
            Task.detached(priority: .userInitiated) { [weak self] in
                let late = await asked.value
                guard let self else { return }
                switch late {
                case .value(let data) where MatchCodec.decode(data) != nil:
                    self.markUp()
                    self.lock.lock()
                    let handler = self.lateHandler
                    self.lock.unlock()
                    handler?()
                case .value, .failed:
                    self.markDown()
                case .timedOut:
                    // Still saying hello: the greeting decides whether it is down.
                    if self.currentState != .unknown { self.markDown() }
                }
            }
            return matches
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
        var status = await local.status()
        if signatureRefused { status.problem = Self.signatureProblem }
        return status
    }

    // MARK: Why the service is not used

    /// NSXPCConnectionCodeSigningRequirementFailure: the other end is not
    /// signed the way this app is (one app re-signed, the others not).
    static let codeSigningFailure = 4102
    static let signatureProblem = "The index service is signed differently from this app, so the app searches its own copy. Run: update"

    private var signatureRefusedFlag = false

    /// Whether the service was turned away for its signature.
    var signatureRefused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return signatureRefusedFlag
    }

    /// Notes why a call failed, so Settings can say it rather than show the
    /// service as merely down.
    fileprivate func noteFailure(_ error: Error) {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain, error.code == Self.codeSigningFailure else { return }
        lock.lock()
        signatureRefusedFlag = true
        lock.unlock()
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
        // Reading this program's own signature can take a while on a slow
        // disk the first time; it is read here, before the lock, so nothing
        // that only wants the lock (the main thread among them) waits on it.
        let requirement = Self.serviceRequirement
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
                fresh = newConnection(requirement: requirement)
                connection = fresh
            }
        case .down(let since, let retried):
            guard now.timeIntervalSince(retried) >= Self.retryAfter else {
                lock.unlock()
                return false
            }
            state = .down(since: since, retried: now)
            old = connection
            fresh = newConnection(requirement: requirement)
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
    /// What the service must be signed as, read once.
    static let serviceRequirement: String? = CodeSigning.requirement(allowing: [IndexServiceName.bundleID], signer: CodeSigning.own)

    private func newConnection(requirement: String?) -> NSXPCConnection? {
        guard let serviceName else { return nil }
        let connection = NSXPCConnection(machServiceName: serviceName, options: [])
        connection.remoteObjectInterface = IndexXPC.serviceInterface()
        connection.exportedInterface = IndexXPC.eventsInterface()
        connection.exportedObject = EventReceiver(client: self)
        if let requirement {
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
        // The service must run as this user (read from the audit token, which
        // it cannot forge); otherwise it is never asked again.
        if !reply.0 || !CodeSigning.acceptsPeer(uid: connection.effectiveUserIdentifier) {
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
        signatureRefusedFlag = false
        if state != .refused { state = .up }
        lock.unlock()
        scheduleCopyRelease()
    }

    /// Lets the copy go when `copyRelease` says so, or checks again when it
    /// may; one check waits at a time, and none while there is no copy.
    func scheduleCopyRelease() {
        lock.lock()
        guard !releaseScheduled else {
            lock.unlock()
            return
        }
        let decision = Self.copyRelease(up: state == .up, loaded: local.isLoaded, lastLocalUse: lastLocalUse, now: Date())
        if case .after = decision { releaseScheduled = true }
        lock.unlock()
        switch decision {
        case .keep:
            break
        case .now:
            local.releaseIfIdle()
        case .after(let wait):
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + wait + 1) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.releaseScheduled = false
                self.lock.unlock()
                self.scheduleCopyRelease()
            }
        }
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
        scheduleCopyRelease()
    }

    fileprivate func receivedChange(_ files: Int) {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?(files)
    }

    /// A call's outcome: an answer, a connection error, or no answer in time.
    enum Reply<T> {
        case value(T)
        case failed
        case timedOut
    }

    private enum SearchRace {
        case service(Reply<Data>)
        case copy([IndexMatch])
    }

    private func reply<T>(timeout: TimeInterval, _ body: @escaping (IndexServiceXPC, @escaping (T) -> Void) -> Void) async -> Reply<T> {
        guard let connection = currentConnection() else { return .failed }
        let result: Reply<T>? = await withCheckedContinuation { (continuation: CheckedContinuation<Reply<T>?, Never>) in
            let once = Once(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.noteFailure(error)
                once.resume(.failed)
            }
            guard let service = proxy as? IndexServiceXPC else {
                once.resume(.failed)
                return
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { once.resume(.timedOut) }
            body(service) { value in once.resume(.value(value)) }
        }
        return result ?? .failed
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
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.noteFailure(error)
                once.resume(nil)
            }
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
        // Reading and decoding the snapshot blocks for as long as the disk
        // takes; off the concurrency pool, so searches typed meanwhile (the
        // service's answers among them) still get a thread.
        let found: Loaded? = await BlockingWork.run(qos: .userInitiated) {
            SnapshotAdoption.load(locations, exclusions: exclusions, order: order).map { Loaded(index: $0.index, origin: $0.origin) }
        }
        guard let found else {
            return FileIndex(roots: locations.roots, exclusions: exclusions, order: order)
        }
        // Whatever the rules leave out goes, from any snapshot (never written here).
        await found.index.pruneExcluded()
        return found.index
    }

    private struct Loaded: Sendable {
        let index: FileIndex
        let origin: SnapshotAdoption.Origin
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

/// When an app may warm its connection to the service: on use (the window
/// opening), never on a timer, and at most once a minute. A search makes the
/// connection itself when it is missing, so warming only saves the first
/// search a moment; it is not worth a wake-up while the app sits unused.
public struct WarmGate: Sendable {
    public static let minimumGap: TimeInterval = 60
    private var last: Date?

    public init() {}

    public mutating func shouldWarm(at now: Date = Date()) -> Bool {
        if let last, now.timeIntervalSince(last) < Self.minimumGap, now >= last { return false }
        last = now
        return true
    }
}
