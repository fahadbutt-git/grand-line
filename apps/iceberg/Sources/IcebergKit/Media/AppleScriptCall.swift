import Foundation

/// Runs an AppleScript off the main thread with a hard time limit.
///
/// Apple Events block until the other app answers: a busy player, or the
/// Automation consent prompt, would hold the caller for up to two minutes.
/// So scripts run in `/usr/bin/osascript` through CommandRunner, on a
/// background queue, and the process is killed after `timeout`. macOS still
/// asks about Iceberg (the parent) for the Automation permission.
public enum AppleScriptCall {
    /// The process's limit. Scripts also set `with timeout` a little shorter.
    public static let timeout: TimeInterval = 3

    public struct Outcome: Equatable, Sendable {
        /// What the script returned, when it ran.
        public var output: String?
        /// What the run says about AppleScript access; nil when it says
        /// nothing (it timed out, for example while the consent prompt waits).
        public var status: AppleScriptStatus?
    }

    /// The shell command for `source`, one `-e` per line.
    public static func command(for source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return (["/usr/bin/osascript"] + lines.flatMap { ["-e", shellQuoted($0)] }).joined(separator: " ")
    }

    /// Runs `source` and waits for it, at most about `timeout` seconds.
    /// Never call it on the main thread.
    public static func run(_ source: String, runner: CommandRunner = CommandRunner(),
                           timeout: TimeInterval = AppleScriptCall.timeout) -> Outcome {
        outcome(of: runner.run(command(for: source), timeout: timeout))
    }

    public static func outcome(of result: CommandResult) -> Outcome {
        if result.launchError != nil { return Outcome(output: nil, status: .failed("osascript could not start")) }
        if result.timedOut { return Outcome(output: nil, status: nil) }
        if result.exitCode == 0 {
            return Outcome(output: result.stdout.trimmingCharacters(in: .newlines), status: .working)
        }
        let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = text.split(whereSeparator: { $0.isNewline }).first.map(String.init)
        return Outcome(output: nil, status: AppleScriptStatus.from(errorNumber: errorNumber(fromStderr: text) ?? -1,
                                                                   message: message.map(CommandOutputParser.clean)))
    }

    /// osascript ends its error line with the number: `... (-1743)`.
    public static func errorNumber(fromStderr text: String) -> Int? {
        guard let close = text.lastIndex(of: ")"), let open = text[..<close].lastIndex(of: "(") else { return nil }
        return Int(text[text.index(after: open)..<close])
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
