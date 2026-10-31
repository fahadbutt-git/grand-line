import Foundation

/// What one widget has done since Iceberg started, for Settings ›
/// Diagnostics: how often it ran, how long it took, and what it last said.
/// This is what makes a widget that drains the battery easy to find.
public struct WidgetStats: Equatable, Sendable {
    public var runs = 0
    public var failures = 0
    public var timeouts = 0
    /// Runs held back: sleep, Low Power Mode, or a backoff after failures.
    public var skipped = 0
    public var totalRuntime: TimeInterval = 0
    public var lastRun: Date?
    public var lastDuration: TimeInterval?
    /// The start of its last output, cleaned of colour codes.
    public var lastOutput: String?
    public var lastError: String?
    public var lastErrorAt: Date?
    /// Stream widgets: lines received and how often the script was started.
    public var streamLines = 0
    public var streamStarts = 0

    public static let maxOutputLength = 400

    public init() {}

    public var averageRuntime: TimeInterval? {
        runs > 0 ? totalRuntime / Double(runs) : nil
    }

    /// One finished run of an interval or signal widget.
    public mutating func record(_ result: CommandResult, display: WidgetDisplay, at now: Date) {
        runs += 1
        totalRuntime += result.duration
        lastRun = now
        lastDuration = result.duration
        let output = Self.excerpt(result.stdout)
        if !output.isEmpty || !display.failed { lastOutput = output }
        if result.timedOut { timeouts += 1 }
        if display.failed {
            failures += 1
            lastError = CommandOutputParser.failureReason(result)
            if result.exitCode != nil, result.exitCode != 0, !display.text.isEmpty, lastError?.hasPrefix("Command failed") == true {
                lastError = display.text + " (exit \(result.exitCode!))"
            }
            lastErrorAt = now
        }
    }

    /// A stream was started.
    public mutating func recordStreamStart(at now: Date) {
        streamStarts += 1
        lastRun = now
    }

    /// One line from a stream.
    public mutating func recordStreamLine(_ line: String, at now: Date) {
        streamLines += 1
        lastOutput = Self.excerpt(line)
    }

    /// A stream ended. One that Iceberg stopped is not a failure.
    public mutating func recordStreamExit(_ exit: StreamExit, at now: Date) {
        runs += 1
        totalRuntime += exit.duration
        lastDuration = exit.duration
        if exit.isFailure {
            failures += 1
            lastError = exit.reason
            lastErrorAt = now
        }
    }

    public mutating func recordSkip() { skipped += 1 }

    /// Up to five lines and `maxOutputLength` characters, without colour codes.
    static func excerpt(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline })
            .prefix(5)
            .map { CommandOutputParser.clean(String($0)) }
        let joined = lines.joined(separator: "\n")
        return joined.count > maxOutputLength ? String(joined.prefix(maxOutputLength - 1)) + "…" : joined
    }

    /// "12 runs, 0.21 s on average" for the Diagnostics list.
    public var summary: String {
        var parts: [String] = []
        parts.append(runs == 1 ? "1 run" : "\(runs) runs")
        if let avg = averageRuntime { parts.append(Self.seconds(avg) + " on average") }
        if streamLines > 0 { parts.append(streamLines == 1 ? "1 line" : "\(streamLines) lines") }
        if failures > 0 { parts.append(failures == 1 ? "1 failure" : "\(failures) failures") }
        if timeouts > 0 { parts.append(timeouts == 1 ? "1 timed out" : "\(timeouts) timed out") }
        if skipped > 0 { parts.append("\(skipped) held back") }
        return parts.joined(separator: ", ")
    }

    static func seconds(_ s: TimeInterval) -> String {
        if s < 0.01 { return "under 0.01 s" }
        if s < 10 { return String(format: "%.2f s", s) }
        return String(format: "%.0f s", s)
    }
}
