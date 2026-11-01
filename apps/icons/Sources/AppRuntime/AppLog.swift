import Foundation

/// One line per event in `~/Library/Logs/grand-line/<name>.log`, where the
/// rest of the package keeps its logs. Writes happen on a background queue,
/// never on the caller's thread, and the file starts again past 256 KB.
public final class AppLog: @unchecked Sendable {
    public let url: URL
    private let queue = DispatchQueue(label: "AppRuntime.AppLog", qos: .utility)
    static let maxBytes = 256 * 1024

    /// `home` defaults to NSHomeDirectory(), which follows CFFIXED_USER_HOME
    /// (the journeys' fixture home).
    public init(name: String, home: String = NSHomeDirectory()) {
        url = URL(fileURLWithPath: home).appendingPathComponent("Library/Logs/grand-line/\(name).log")
    }

    public func write(_ message: String, at date: Date = Date()) {
        let line = AppLog.line(message, at: date)
        let url = self.url
        queue.async { AppLog.append(line, to: url) }
    }

    /// Waits for the lines written so far (tests, and before exiting).
    public func flush() {
        queue.sync {}
    }

    static func line(_ message: String, at date: Date) -> String {
        let stamp = ISO8601DateFormatter().string(from: date)
        return "\(stamp) \(message)\n"
    }

    static func append(_ line: String, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0, size < maxBytes, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// A notification in the corner of the screen, as the package's shell
/// commands post them (`osascript`, so no permission prompt of the app's
/// own). It never takes the keyboard or brings a window forward.
public enum QuietNotice {
    public static func post(title: String, message: String) {
        guard ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1" else { return }
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                                 "-e", "end run", title, message]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }
    }
}

/// SIGTERM (an update replacing the app, `pkill`, logout) as a normal quit:
/// the app's own quit path runs, so it saves and its run record says it
/// ended cleanly instead of looking like a crash.
public enum TerminationSignal {
    public static func handle(on queue: DispatchQueue = .main, _ quit: @escaping @Sendable () -> Void) -> DispatchSourceSignal {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        source.setEventHandler(handler: quit)
        source.resume()
        return source
    }
}
