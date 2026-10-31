import Foundation

/// Runs a tool and waits for it, off the main thread.
public enum ProcessRunner {
    public struct Result: Equatable, Sendable {
        public let status: Int32
        public let errorText: String

        public var succeeded: Bool { status == 0 }
    }

    public static func run(_ command: ToolCommand) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
            process.terminationHandler = { finished in
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(
                    status: finished.terminationStatus, errorText: String(decoding: data, as: UTF8.self)
                ))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    /// Starts a tool that lives on by itself (a terminal window, a transcode job).
    public static func launch(_ command: ToolCommand) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
