import Foundation

/// Something that runs a program with arguments (never through a shell
/// string) and waits for it, with a time limit. ShellRunner is the real one;
/// tests pass a fake that answers from a script.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws -> ShellOutput
}

extension ShellRunner: CommandRunning {}
