import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs a tool (bsdtar, ditto, osascript) in a process group of its own and
/// waits for it off the calling thread.
///
/// - stdout and stderr are read while the tool runs, each on its own thread,
///   so a tool that prints a lot (bsdtar's "Can't open" line per unreadable
///   file) never fills a pipe and stops.
/// - Cancelling the calling task (Stop in the tasks popover) sends SIGTERM to
///   the whole group, so anything the tool started stops too, then SIGKILL
///   if it is still running a few seconds later; `run` then throws
///   CancellationError.
///
/// ```swift
/// let output = try await ChildProcess.run("/usr/bin/bsdtar", ["-x", "-f", path])
/// ```
public final class ChildProcess: @unchecked Sendable {
    public struct Output: Sendable, Equatable {
        public let status: Int32
        public let output: Data
        public let errors: Data

        public var succeeded: Bool { status == 0 }
        public var errorText: String { String(decoding: errors, as: UTF8.self) }
    }

    public enum Failure: Error, Equatable {
        /// posix_spawn refused: the errno it gave.
        case couldNotStart(Int32)
    }

    /// Error text kept from a tool, at most; the rest is read and dropped.
    static let errorLimit = 1 << 20

    private let lock = NSLock()
    private let pid: pid_t
    private var exited = false
    private var terminated = false
    private let readers = DispatchGroup()
    private let collected = Collected()

    /// Starts the tool. `environment` nil passes Nexus's own.
    init(_ executable: String, _ arguments: [String], environment: [String: String]?) throws {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { throw Failure.couldNotStart(errno) }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            throw Failure.couldNotStart(errno)
        }
        for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        #else
        var actions = posix_spawn_file_actions_t()
        var attributes = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        // Its own process group (Stop ends the whole group), default signal
        // handling and an empty mask, and no other descriptor of Nexus's.
        var flags = Int32(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        #if canImport(Darwin)
        flags |= Int32(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var mostSignals = sigset_t()
        sigfillset(&mostSignals)
        sigdelset(&mostSignals, SIGKILL)
        sigdelset(&mostSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &mostSignals)

        let environment = environment ?? ProcessInfo.processInfo.environment
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        var child: pid_t = 0
        let status = posix_spawn(&child, executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])
        guard status == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw Failure.couldNotStart(status)
        }
        pid = child
        read(outPipe[0], into: .output)
        read(errPipe[0], into: .errors)
    }

    /// Runs a tool to the end; cancelling the task stops it.
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) async throws -> Output {
        try Task.checkCancellation()
        let child = try ChildProcess(executable, arguments, environment: environment)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let output = child.waitForExit()
                    if child.wasTerminated {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: output)
                    }
                }
            }
        } onCancel: {
            child.terminate()
        }
    }

    /// Runs a tool to the end on this thread (for callers that are not tasks,
    /// such as a file promise being written).
    public static func runAndWait(_ executable: String, _ arguments: [String], environment: [String: String]? = nil) throws -> Output {
        try ChildProcess(executable, arguments, environment: environment).waitForExit()
    }

    var wasTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    /// Stops the tool and everything it started: SIGTERM to its group, then
    /// SIGKILL after three seconds if it has not gone. A tool that has already
    /// ended is left alone (its pid is never signalled once reaped).
    public func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard !exited else { return }
        terminated = true
        kill(-pid, SIGTERM)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [self] in
            lock.lock()
            defer { lock.unlock() }
            if !exited { kill(-pid, SIGKILL) }
        }
    }

    /// Waits for the tool to end and for both pipes to be read to the end.
    func waitForExit() -> Output {
        // Wait without reaping, so the pid (and the group) cannot be reused
        // while `terminate` may still signal it.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
        lock.lock()
        exited = true
        lock.unlock()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        readers.wait()
        return Output(status: Self.exitCode(status), output: collected.data(.output), errors: collected.data(.errors))
    }

    /// The exit status, or 128 plus the signal that ended it.
    static func exitCode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    enum Stream: Sendable { case output, errors }

    private func read(_ fd: Int32, into stream: Stream) {
        readers.enter()
        let collected = self.collected
        let readers = self.readers
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = buffer.withUnsafeMutableBytes { Darwin_read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    collected.append(buffer, count: count, to: stream == .output, limit: stream == .errors ? ChildProcess.errorLimit : nil)
                } else if count == 0 || errno != EINTR {
                    break
                }
            }
            close(fd)
            readers.leave()
        }
    }

    final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var output = Data()
        private var errors = Data()

        func append(_ bytes: [UInt8], count: Int, to isOutput: Bool, limit: Int?) {
            lock.lock()
            defer { lock.unlock() }
            if isOutput {
                output.append(contentsOf: bytes[0..<count])
            } else if errors.count < (limit ?? .max) {
                errors.append(contentsOf: bytes[0..<min(count, (limit ?? .max) - errors.count)])
            }
        }

        func data(_ stream: Stream) -> Data {
            lock.lock()
            defer { lock.unlock() }
            return stream == .output ? output : errors
        }
    }
}

/// read(2), named apart from the instance method above.
@inline(__always)
private func Darwin_read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.read(fd, buffer, count)
    #else
    return Glibc.read(fd, buffer, count)
    #endif
}
