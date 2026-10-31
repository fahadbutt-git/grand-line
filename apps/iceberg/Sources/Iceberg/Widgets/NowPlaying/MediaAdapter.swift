import Foundation
import IcebergKit

/// Runs mediaremote-adapter's `stream` and hands each line to the main thread.
///
/// Since macOS 15.4 only Apple-entitled processes may read Now Playing from
/// the private MediaRemote framework. The adapter (ungive/mediaremote-adapter,
/// BSD-3) loads a small framework into `/usr/bin/perl`, which is entitled,
/// and prints changes as JSON lines. It waits on MediaRemote's own
/// notifications, so it uses no CPU while nothing changes.
final class MediaAdapter {
    struct Location {
        let script: URL
        let framework: URL
    }

    /// The adapter's script and framework, or nil when they cannot be found.
    ///
    /// The script is in the app's Resources. The library is looked for, in
    /// order: a framework inside the app (`build.sh` puts one there), then the
    /// SwiftPM library beside the app's program or in the package's own
    /// `.build/release` (how Grand Line's setup builds it). A bare library is
    /// wrapped as a framework in Application Support, the shape the script
    /// expects, and refreshed whenever the library is newer.
    static func bundled(in bundle: Bundle = .main) -> Location? {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl") else { return nil }
        let fm = FileManager.default
        if let frameworks = bundle.privateFrameworksURL {
            let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
            if fm.fileExists(atPath: framework.appendingPathComponent("MediaRemoteAdapter").path) {
                return Location(script: script, framework: framework)
            }
        }
        let name = "libMediaRemoteAdapter.dylib"
        var candidates: [URL] = []
        if let exe = bundle.executableURL { candidates.append(exe.deletingLastPathComponent().appendingPathComponent(name)) }
        if let res = bundle.resourceURL { candidates.append(res.appendingPathComponent(name)) }
        candidates.append(fm.homeDirectoryForCurrentUser.appendingPathComponent(".grand-line/apps/iceberg/.build/release/\(name)"))
        guard let library = candidates.first(where: { fm.fileExists(atPath: $0.path) }),
              let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let framework = support.appendingPathComponent("Iceberg/MediaRemoteAdapter.framework")
        let binary = framework.appendingPathComponent("MediaRemoteAdapter")
        do {
            try fm.createDirectory(at: framework, withIntermediateDirectories: true)
            let source = (try? fm.attributesOfItem(atPath: library.path)[.modificationDate] as? Date) ?? .distantPast
            let copied = (try? fm.attributesOfItem(atPath: binary.path)[.modificationDate] as? Date) ?? .distantPast
            if source > copied || !fm.fileExists(atPath: binary.path) {
                let staging = framework.appendingPathComponent(".MediaRemoteAdapter.new")
                try? fm.removeItem(at: staging)
                try fm.copyItem(at: library, to: staging)
                if fm.fileExists(atPath: binary.path) {
                    _ = try fm.replaceItemAt(binary, withItemAt: staging)
                } else {
                    try fm.moveItem(at: staging, to: binary)
                }
            }
        } catch {
            Log.info("Could not prepare the Now Playing adapter: \(error.localizedDescription)")
            return nil
        }
        return Location(script: script, framework: framework)
    }

    private let location: Location
    private let onLine: @MainActor (String) -> Void
    private let onGiveUp: @MainActor () -> Void
    private var process: Process?
    private var quickExits = 0
    private var stopped = false

    init(location: Location, onLine: @escaping @MainActor (String) -> Void, onGiveUp: @escaping @MainActor () -> Void) {
        self.location = location
        self.onLine = onLine
        self.onGiveUp = onGiveUp
    }

    deinit { stop() }

    func start() {
        stopped = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // Debounce merges the bursts some players send when a track changes.
        p.arguments = [location.script.path, location.framework.path, "stream", "--debounce=80"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        let box = LineBox()
        let deliver = onLine
        out.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let lines = box.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { for l in lines { deliver(l) } }
            }
        }
        let started = Date()
        p.terminationHandler = { [weak self] _ in
            let seconds = Date().timeIntervalSince(started)
            DispatchQueue.main.async { [weak self] in self?.ended(after: seconds) }
        }
        do {
            try p.run()
            process = p
        } catch {
            Log.info("Now Playing adapter did not start: \(error.localizedDescription)")
            ended(after: 0)
        }
    }

    func stop() {
        stopped = true
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// Restarts with a growing pause; after three quick failures in a row
    /// the adapter is taken to be broken (a future macOS) and the fallback
    /// takes over.
    private func ended(after seconds: TimeInterval) {
        process = nil
        guard !stopped else { return }
        quickExits = seconds < 10 ? quickExits + 1 : 0
        if quickExits >= 3 {
            Log.info("Now Playing adapter keeps exiting")
            let giveUp = onGiveUp
            MainActor.assumeIsolated { giveUp() }
            return
        }
        let delay = min(60, pow(2, Double(quickExits)))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            self.start()
        }
    }

    /// Sends a MediaRemote command id through the adapter (0 play, 1 pause,
    /// 2 toggle, 4 next, 5 previous). Used when the in-process call is missing.
    func send(_ command: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [location.script.path, location.framework.path, "send", String(command)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}

/// Holds the partial line between reads (reads arrive on one queue at a time).
private final class LineBox: @unchecked Sendable {
    private var buffer = LineBuffer()
    private let lock = NSLock()
    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.append(data)
    }
}
