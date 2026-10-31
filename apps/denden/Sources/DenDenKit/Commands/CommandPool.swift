import Foundation

/// Runs widget commands a few at a time, never two runs of the same widget at
/// once. Opening the panel with 50 widgets queues 50 commands but starts only
/// `maxConcurrent` processes at a time, so the Mac stays quiet.
public final class CommandPool: @unchecked Sendable {
    public typealias Completion = @Sendable (String, CommandResult) -> Void

    private let queue = OperationQueue()
    private let lock = NSLock()
    private var running: Set<String> = []
    private var active = 0
    private var peak = 0
    private let runner: CommandRunner

    public init(runner: CommandRunner = CommandRunner(), maxConcurrent: Int = 4) {
        self.runner = runner
        queue.maxConcurrentOperationCount = max(1, maxConcurrent)
        queue.qualityOfService = .utility
        queue.name = "Den Den widget commands"
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The most commands that ran at the same moment (for the tests).
    public var peakConcurrency: Int { locked { peak } }

    /// True while that widget's command is queued or running.
    public func isBusy(_ id: String) -> Bool { locked { running.contains(id) } }

    /// Queues a run. Returns false, and does nothing, when that widget is
    /// already queued or running.
    @discardableResult
    public func submit(id: String, command: String, timeout: TimeInterval, workingDirectory: URL? = nil,
                       environment: [String: String] = [:], completion: @escaping Completion) -> Bool {
        let accepted = locked { running.insert(id).inserted }
        guard accepted else { return false }
        let runner = self.runner
        queue.addOperation {
            self.locked {
                self.active += 1
                self.peak = max(self.peak, self.active)
            }
            let result = runner.run(command, timeout: timeout, workingDirectory: workingDirectory,
                                    extraEnvironment: environment)
            self.locked {
                self.active -= 1
                self.running.remove(id)
            }
            completion(id, result)
        }
        return true
    }

    /// Waits until everything queued has finished (for the tests).
    public func waitUntilIdle() { queue.waitUntilAllOperationsAreFinished() }
}
