import Foundation

/// Brings back the menu-bar apps (Sight, Iceberg) after a crash. It runs in
/// the index agent, which launchd keeps running: once a minute (a tenth of
/// it as leeway) it reads each app's run record and starts an app that
/// crashed, in the background (`open -g -j`: no window comes forward, the
/// keyboard stays where it is). An app that quit normally, or stays down
/// after a crash loop (`RunRecord`), is left alone.
public final class CrashWatcher: @unchecked Sendable {
    public struct Watched: Sendable {
        public let name: String
        public let bundleID: String
        public init(name: String, bundleID: String) {
            self.name = name
            self.bundleID = bundleID
        }
    }

    public static let interval: TimeInterval = 60

    private let apps: [Watched]
    private let home: String
    private let log: AppLog
    private let queue = DispatchQueue(label: "AppRuntime.CrashWatcher", qos: .background)
    private var timer: DispatchSourceTimer?
    private let launcher: @Sendable (String) -> Void

    public init(apps: [Watched], log: AppLog, home: String = NSHomeDirectory(),
                launcher: (@Sendable (String) -> Void)? = nil) {
        self.apps = apps
        self.home = home
        self.log = log
        self.launcher = launcher ?? CrashWatcher.openInBackground
    }

    public func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(6))
        t.setEventHandler { [weak self] in self?.check() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// One look at every app (the timer calls it; tests call it directly).
    public func check() {
        let folder = CrashGuard.folder(home: home)
        for app in apps {
            let record = CrashGuard.read(folder.appendingPathComponent("\(app.name).json"))
            let alive = record.map { CrashWatcher.isAlive($0.pid) } ?? false
            guard RelaunchDecision.decide(record, alive: alive) == .relaunch else { continue }
            log.write("\(app.name) is not running after a crash; starting it again in the background")
            launcher(app.bundleID)
        }
    }

    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static let openInBackground: @Sendable (String) -> Void = { bundleID in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", "-b", bundleID]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
