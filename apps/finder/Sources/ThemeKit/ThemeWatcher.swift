import Foundation
import IndexKit

/// Publishes the theme again whenever `theme set` changes it or its file is edited.
///
/// ```swift
/// let watcher = ThemeWatcher()
/// watcher.start()
/// for await theme in watcher.themes { apply(theme) }
/// ```
public final class ThemeWatcher: @unchecked Sendable {
    public let location: ThemeLocation
    public let themes: AsyncStream<Theme>

    private let continuation: AsyncStream<Theme>.Continuation
    private let latency: TimeInterval
    private let lock = NSLock()
    private var current: Theme
    private var watcher: FolderWatcher?
    private var task: Task<Void, Never>?

    public init(location: ThemeLocation = ThemeLocation(), latency: TimeInterval = 0.2) {
        self.location = location
        self.latency = latency
        self.current = location.load()
        let (themes, continuation) = AsyncStream.makeStream(of: Theme.self, bufferingPolicy: .bufferingNewest(1))
        self.themes = themes
        self.continuation = continuation
    }

    deinit {
        task?.cancel()
        watcher?.stop()
        continuation.finish()
    }

    /// The theme as last read.
    public var theme: Theme {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Watches the state folder and the themes folder. Returns false if neither can be watched.
    @discardableResult
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard watcher == nil else { return true }
        let folders = [location.stateFile.deletingLastPathComponent(), location.themesFolder]
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !folders.isEmpty else { return false }
        let watcher = FolderWatcher(paths: folders, latency: latency)
        guard watcher.start() else { return false }
        self.watcher = watcher
        let changes = watcher.changes
        task = Task { [weak self] in
            for await _ in changes { self?.reload() }
        }
        return true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel()
        task = nil
        watcher?.stop()
        watcher = nil
    }

    /// Reads the theme again and publishes it if it changed. Returns whether it changed.
    @discardableResult
    public func reload() -> Bool {
        let fresh = location.load()
        lock.lock()
        let changed = fresh != current
        if changed { current = fresh }
        lock.unlock()
        if changed { continuation.yield(fresh) }
        return changed
    }
}
