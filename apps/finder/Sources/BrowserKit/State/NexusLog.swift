import Foundation
import os

/// Clipboard, key and task events: in the system log, and in
/// `~/Library/Logs/grand-line/nexus.log` once Nexus has started it, where the
/// rest of the package keeps its logs. A paste that did nothing can then be
/// read back afterwards (the user journeys print the last lines on a failure).
/// Until `start` names a file, and in the tests, lines go to the system log only.
public enum NexusLog {
    private static let system = Logger(subsystem: "com.grandline.nexus", category: "files")

    /// The log file under a home folder.
    public static func file(home: URL) -> URL {
        home.appendingPathComponent("Library/Logs/grand-line/nexus.log")
    }

    /// The file lines go to from now on; nil writes no file.
    public static func start(file: URL?) {
        state.lock.lock()
        state.file = file
        state.lock.unlock()
        if let file {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
    }

    public static var currentFile: URL? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.file
    }

    /// One line, with the time in front.
    public static func note(_ message: String) {
        system.notice("\(message, privacy: .public)")
        state.lock.lock()
        defer { state.lock.unlock() }
        guard let url = state.file else { return }
        append(line(message), to: url)
    }

    /// "2026-10-31T17:13:30.123Z copy 1 item: report.pdf".
    static func line(_ message: String, at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date) + " " + message.replacingOccurrences(of: "\n", with: " ") + "\n"
    }

    /// The last `count` lines of a log file, oldest first; empty when there is none.
    public static func tail(of url: URL, lines count: Int) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(max(0, count)).map(String.init)
    }

    /// Names for a line: "report.pdf", or "3 items: a, b, c".
    public static func names(_ urls: [URL]) -> String {
        let shown = urls.prefix(5).map(\.lastPathComponent).joined(separator: ", ")
        let more = urls.count > 5 ? ", …" : ""
        return urls.count == 1 ? shown : "\(urls.count) items: \(shown)\(more)"
    }

    private static let state = State()

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var file: URL?
    }

    /// Past 256 KB the file starts again with this line, so it stays small.
    private static func append(_ text: String, to url: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 0, size < 256 * 1024, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
