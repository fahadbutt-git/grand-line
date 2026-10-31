import Foundation

/// The output of a finished command.
public struct ShellOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
}

/// Runs a program, waits for it with a time limit, and stops it when the task
/// that asked is cancelled. The environment puts the Grand Line commands and
/// Homebrew on the PATH, which apps started from Finder do not have.
public struct ShellRunner: Sendable {
    public var environment: [String: String]

    public init(environment: [String: String] = ShellRunner.environment()) {
        self.environment = environment
    }

    public static func environment(paths: GrandLinePaths = GrandLinePaths(), base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let extra = [paths.bin, "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let existing = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var path: [String] = []
        for part in extra + existing where !path.contains(part) { path.append(part) }
        env["PATH"] = path.joined(separator: ":")
        env["HOME"] = env["HOME"] ?? paths.home
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// The bash arguments that run a menu line the way bin/menu does: with
    /// bin-common.sh sourced, so its PATH and variables are set.
    public static func bashArguments(for line: String, paths: GrandLinePaths = GrandLinePaths()) -> [String] {
        ["-c", "source \"$1\" 2>/dev/null; shift; eval \"$1\"", "byakugan", paths.commonShell, line]
    }

    final class Box: @unchecked Sendable {
        let process = Process()
        let pipe = Pipe()
    }

    public func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 3) async throws -> ShellOutput {
        let box = Box()
        let process = box.process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = box.pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let output: ShellOutput = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellOutput, Error>) in
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if box.process.isRunning { box.process.terminate() }
                }
                DispatchQueue.global().async {
                    let data = box.pipe.fileHandleForReading.readDataToEndOfFile()
                    box.process.waitUntilExit()
                    let text = String(decoding: data, as: UTF8.self)
                    continuation.resume(returning: ShellOutput(status: box.process.terminationStatus, stdout: text))
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
        try Task.checkCancellation()
        return output
    }
}
