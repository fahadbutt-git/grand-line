import ArchiveKit
import Foundation

/// Runs a tool and waits for it, off the main thread (ArchiveKit's `ChildProcess`).
public enum ProcessRunner {
    public struct Result: Equatable, Sendable {
        public let status: Int32
        public let errorText: String

        public var succeeded: Bool { status == 0 }
    }

    /// stdout and stderr are both read while the tool runs, so one that
    /// prints a lot never stops on a full pipe. Cancelling the task ends the
    /// tool's whole process group and throws CancellationError.
    public static func run(_ command: ToolCommand) async throws -> Result {
        let output = try await ChildProcess.run(command.executable, command.arguments)
        return Result(status: output.status, errorText: output.errorText)
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
