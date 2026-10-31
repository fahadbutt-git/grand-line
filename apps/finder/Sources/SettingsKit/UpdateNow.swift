import AppKit
import SwiftUI

/// Runs a program with an argument list (never through a shell) and hands
/// back each line it prints as it prints it.
public enum ToolRunner {
    /// - Parameters:
    ///   - line: called on the main thread with every line of output.
    ///   - done: called on the main thread with the exit status (-1 when it could not start).
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:],
                           line: @escaping @MainActor (String) -> Void, done: @escaping @MainActor (Int32) -> Void) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            for text in buffer.append(data) {
                DispatchQueue.main.async { MainActor.assumeIsolated { line(text) } }
            }
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            let lines = buffer.append(rest) + buffer.flush()
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for text in lines { line(text) }
                    done(status)
                }
            }
        }
        do {
            try process.run()
        } catch {
            let reason = "Could not start \(executable.lastPathComponent): \(error.localizedDescription)"
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    line(reason)
                    done(-1)
                }
            }
        }
    }

    /// Splits output into lines across reads, behind a lock.
    final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()

        func append(_ data: Data) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.append(text) }
            }
            return lines
        }

        func flush() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            let text = String(decoding: pending, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            pending = Data()
            return text.isEmpty ? [] : [text]
        }
    }
}

/// "Update now": `grandline update --apps-only --notify`, the package's own
/// apps rebuilt from the latest sources, with the last line it printed shown.
@MainActor
public final class UpdateModel: ObservableObject {
    @Published public private(set) var running = false
    @Published public private(set) var lastLine: String?
    @Published public private(set) var failed = false

    public let command: URL
    public static let arguments = ["update", "--apps-only", "--notify"]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        command = home.appendingPathComponent(".grand-line/bin/grandline")
    }

    public func run() {
        guard !running else { return }
        guard FileManager.default.isExecutableFile(atPath: command.path) else {
            failed = true
            lastLine = "grandline is not installed at \(command.path)."
            return
        }
        running = true
        failed = false
        lastLine = "Starting the update…"
        ToolRunner.run(command, Self.arguments, line: { [weak self] text in
            self?.lastLine = text
        }, done: { [weak self] status in
            guard let self else { return }
            self.running = false
            self.failed = status != 0
            if status != 0, self.lastLine == nil { self.lastLine = "The update stopped (exit status \(status))." }
            if status == 0, self.lastLine == "Starting the update…" { self.lastLine = "Up to date." }
        })
    }
}

/// The Update section both apps end their Advanced pane with.
public struct UpdateSection: View {
    @EnvironmentObject private var theme: SettingsTheme
    @ObservedObject var model: UpdateModel
    let idPrefix: String
    let note: String

    public init(model: UpdateModel, idPrefix: String, note: String) {
        self.model = model
        self.idPrefix = idPrefix
        self.note = note
    }

    public var body: some View {
        SettingsSection("Update", note: note) {
            SettingsRow("Update the package's apps", detail: "Runs grandline update --apps-only --notify.") {
                HStack(spacing: 8) {
                    if model.running { ProgressView().controlSize(.small) }
                    Button(model.running ? "Updating…" : "Update now") { model.run() }
                        .disabled(model.running)
                        .accessibilityIdentifier("\(idPrefix).settings.update")
                }
            }
            if let line = model.lastLine {
                SettingsRow(line, symbol: model.failed ? "exclamationmark.triangle" : (model.running ? "arrow.triangle.2.circlepath" : "checkmark.circle"))
                    .accessibilityIdentifier("\(idPrefix).settings.update.status")
            }
        }
    }
}

/// Opens a folder in the file viewer, making it first if needed.
@MainActor
public enum FolderOpener {
    public static func open(_ folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
