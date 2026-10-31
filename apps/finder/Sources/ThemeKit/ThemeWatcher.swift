import Foundation
import IndexKit

/// Publishes the theme again whenever `theme set` changes it or its file is
/// edited (at once on the `com.grandline.theme.changed` notification that
/// `theme set` and `theme apply` post, else when the file watch notices), and, while the theme follows macOS (`ThemeLocation.followFile`),
/// whenever the system switches between dark and light: the variant for the
/// new appearance is shown at once, and one app runs `theme mode` so the rest
/// of the package follows too.
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
    private var systemIsDark: Bool
    private var appearanceObserver: (any NSObjectProtocol)?
    private var changeObserver: (any NSObjectProtocol)?

    /// Posted by the `theme` command once a new theme is rendered.
    public static let changedNotification = Notification.Name(ThemeSpec.changedNotification)

    public init(location: ThemeLocation = ThemeLocation(), latency: TimeInterval = 0.2) {
        self.location = location
        self.latency = latency
        let dark = SystemAppearance.isDark()
        self.systemIsDark = dark
        self.current = location.load(systemIsDark: dark)
        let (themes, continuation) = AsyncStream.makeStream(of: Theme.self, bufferingPolicy: .bufferingNewest(1))
        self.themes = themes
        self.continuation = continuation
    }

    deinit {
        task?.cancel()
        watcher?.stop()
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
        if let changeObserver { DistributedNotificationCenter.default().removeObserver(changeObserver) }
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
        if appearanceObserver == nil {
            appearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: SystemAppearance.changedNotification, object: nil, queue: nil
            ) { [weak self] _ in
                guard let watcher = self else { return }
                // The default is written as the notification goes out; read it a moment later.
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) { [weak watcher] in
                    watcher?.systemAppearanceChanged(isDark: SystemAppearance.isDark())
                }
            }
        }
        if changeObserver == nil {
            // The theme command has written the state file and rendered the
            // templates before it posts, so reading now sees the new theme.
            changeObserver = DistributedNotificationCenter.default().addObserver(
                forName: Self.changedNotification, object: nil, queue: nil
            ) { [weak self] _ in
                self?.reload()
            }
        }
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
        if let appearanceObserver { DistributedNotificationCenter.default().removeObserver(appearanceObserver) }
        appearanceObserver = nil
        if let changeObserver { DistributedNotificationCenter.default().removeObserver(changeObserver) }
        changeObserver = nil
    }

    /// macOS switched between dark and light. While the theme follows macOS,
    /// the matching variant shows now, and the `theme` command is run (by
    /// whichever app gets there first) to switch everything else.
    public func systemAppearanceChanged(isDark: Bool) {
        lock.lock()
        let changed = systemIsDark != isDark
        systemIsDark = isDark
        lock.unlock()
        guard changed, location.followsSystem() else { return }
        reload()
        let location = self.location
        Task.detached(priority: .utility) {
            await ThemeFollow.switchIfNeeded(location: location, systemIsDark: isDark)
        }
    }

    /// Reads the theme again and publishes it if it changed. Returns whether it changed.
    @discardableResult
    public func reload() -> Bool {
        lock.lock()
        let dark = systemIsDark
        lock.unlock()
        let fresh = location.load(systemIsDark: dark)
        lock.lock()
        let changed = fresh != current
        if changed { current = fresh }
        lock.unlock()
        if changed { continuation.yield(fresh) }
        return changed
    }
}
