import Foundation
import os
import IcebergKit

/// Problems go to the system log and to `~/Library/Logs/grand-line/iceberg.log`,
/// where the rest of the package keeps its logs.
enum Log {
    static let system = Logger(subsystem: "com.grandline.iceberg", category: "iceberg")

    static var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/grand-line/iceberg.log")
    }

    static func info(_ message: String) {
        system.info("\(message, privacy: .public)")
    }

    /// Writes config problems once per reload, so the file shows the current set.
    static func issues(_ issues: [ConfigIssue], context: String) {
        guard !issues.isEmpty else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        var text = ""
        for i in issues {
            text += "\(stamp) \(context) \(i.severity.rawValue): \(i.description)\n"
            system.notice("\(context, privacy: .public) \(i.description, privacy: .public)")
        }
        append(text)
    }

    private static func append(_ text: String) {
        let url = file
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Keep the log small: past 256 KB it starts again with this entry.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size < 256 * 1024, let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
