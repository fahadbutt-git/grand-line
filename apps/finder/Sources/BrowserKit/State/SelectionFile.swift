import Foundation

/// ~/.local/state/grand-line/nexus-selection: the selection while Nexus is
/// frontmost, one POSIX path per line, rewritten on every change. The package's
/// scripts (transcode, Sight) read it.
public struct SelectionFile: Sendable {
    public let url: URL
    private let lastWritten: LastWritten

    public init(url: URL) {
        self.url = url
        self.lastWritten = LastWritten()
    }

    public static func contents(_ paths: [String]) -> String {
        paths.isEmpty ? "" : paths.joined(separator: "\n") + "\n"
    }

    /// Writes atomically; skips the write when nothing changed. Items inside
    /// archives have no path on disk and are left out.
    public func write(_ items: [FileItem]) {
        let text = Self.contents(items.filter { !$0.isInArchive }.map(\.url.path))
        guard lastWritten.swap(text) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    public func read() -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// The last text written, behind a lock so any thread may write.
    final class LastWritten: @unchecked Sendable {
        private let lock = NSLock()
        private var text: String?

        /// Stores the text; returns false when it was already the same.
        func swap(_ new: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if text == new { return false }
            text = new
            return true
        }
    }
}
