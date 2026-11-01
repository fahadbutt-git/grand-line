import Foundation

/// The output of a finished command.
public struct ShellOutput: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    /// The program printed more than `ShellRunner.maxOutput`: `stdout` holds
    /// the first part and the program was stopped.
    public let truncated: Bool

    public init(status: Int32, stdout: String, truncated: Bool = false) {
        self.status = status
        self.stdout = stdout
        self.truncated = truncated
    }
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
        // The commands find the package through GRAND_LINE_LINK (lib/paths.sh).
        if paths.isBundledPackage { env["GRAND_LINE_LINK"] = paths.package }
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// The bash arguments that run a menu line the way bin/menu does: with
    /// bin-common.sh sourced, so its PATH and variables are set.
    public static func bashArguments(for line: String, paths: GrandLinePaths = GrandLinePaths()) -> [String] {
        ["-c", "source \"$1\" 2>/dev/null; shift; eval \"$1\"", "sight", paths.commonShell, line]
    }

    /// Output beyond this is not read: the program is stopped and the result
    /// says it was cut short.
    public static let maxOutput = 1 << 20
    /// How long a stopped program has between SIGTERM and SIGKILL.
    public static let killAfter: TimeInterval = 2
    /// The status of a program stopped for its time limit or a cancellation.
    public static let stoppedStatus: Int32 = 15

    /// One run: the child is the leader of its own process group, so a stop
    /// reaches everything it started (osascript under a shell, a script's own
    /// children), first with SIGTERM and two seconds later with SIGKILL.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ShellOutput, Error>?
        private var pid: pid_t = 0
        private var stopping = false
        private var exited = false
        /// The output is no longer read after a stop's grace time: something
        /// outside the group may hold the pipe open forever.
        private var abandoned = false

        func hold(_ continuation: CheckedContinuation<ShellOutput, Error>) {
            lock.lock(); self.continuation = continuation; lock.unlock()
        }

        /// A stop asked for before the program started (a cancelled search) applies now.
        func launched(_ pid: pid_t) {
            lock.lock()
            self.pid = pid
            let stopNow = stopping
            lock.unlock()
            if stopNow { terminate(pid) }
        }

        func markExited() {
            lock.lock(); exited = true; lock.unlock()
        }

        var isAbandoned: Bool {
            lock.lock(); defer { lock.unlock() }
            return abandoned
        }

        var wasStopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopping
        }

        /// Answers once.
        func finish(_ result: Result<ShellOutput, Error>) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
        }

        /// SIGTERM to the whole group now, SIGKILL after the grace time, and
        /// then the output is let go.
        func stop() {
            lock.lock()
            let target = pid
            let first = !stopping
            stopping = true
            lock.unlock()
            guard target > 0, first else { return }
            terminate(target)
        }

        private func terminate(_ target: pid_t) {
            kill(-target, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + ShellRunner.killAfter) { [self] in
                lock.lock()
                let gone = exited
                abandoned = true
                lock.unlock()
                // The leader may be gone while others in its group live on.
                kill(-target, SIGKILL)
                if !gone { kill(target, SIGKILL) }
            }
        }
    }

    /// The exit status, or the signal that ended the program.
    static func decode(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : signal
    }

    public func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 3) async throws -> ShellOutput {
        let box = Box()
        let environment = self.environment
        let output: ShellOutput = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellOutput, Error>) in
                box.hold(continuation)
                let spawned: (pid: pid_t, reader: Int32)
                do {
                    spawned = try Self.spawn(executable, arguments, environment: environment)
                } catch {
                    box.finish(.failure(error))
                    return
                }
                let pid = spawned.pid
                let reader = spawned.reader
                box.launched(pid)
                // Also when the program itself has ended but something it
                // started still holds its output open.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { box.stop() }
                DispatchQueue.global().async {
                    let (data, truncated, early) = Self.collect(reader, pid: pid, box: box)
                    var status: Int32 = 0
                    if let early {
                        status = early
                    } else {
                        var raw: Int32 = 0
                        while waitpid(pid, &raw, 0) < 0, errno == EINTR {}
                        status = Self.decode(raw)
                    }
                    box.markExited()
                    // Stopped by us, by signal: the time limit's status, as before.
                    if box.wasStopped, status == SIGKILL || status == SIGTERM { status = Self.stoppedStatus }
                    let text = String(decoding: data, as: UTF8.self)
                    box.finish(.success(ShellOutput(status: status, stdout: text, truncated: truncated)))
                }
            }
        } onCancel: {
            box.stop()
        }
        try Task.checkCancellation()
        return output
    }

    /// Reads the output up to `maxOutput`, a tenth of a second at a time, so
    /// a stop's grace time can end the read even when a process outside the
    /// group holds the pipe. Returns the bytes, whether they were cut short,
    /// and the exit status when the program was reaped meanwhile.
    static func collect(_ reader: Int32, pid: pid_t, box: Box) -> (Data, Bool, Int32?) {
        defer { close(reader) }
        var data = Data()
        var truncated = false
        var status: Int32?
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if status == nil {
                var raw: Int32 = 0
                if waitpid(pid, &raw, WNOHANG) == pid {
                    status = decode(raw)
                    box.markExited()
                }
            }
            var poller = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, 100)
            if ready > 0 {
                let count = buffer.withUnsafeMutableBytes { read(reader, $0.baseAddress, $0.count) }
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR || errno == EAGAIN { continue }
                    break
                }
                let room = maxOutput - data.count
                if count > room {
                    data.append(contentsOf: buffer[0..<max(0, room)])
                    truncated = true
                    box.stop()
                    break
                }
                data.append(contentsOf: buffer[0..<count])
            } else if ready < 0, errno != EINTR {
                break
            }
            if box.isAbandoned { break }
        }
        return (data, truncated, status)
    }

    struct SpawnError: Error, CustomStringConvertible {
        let code: Int32
        var description: String { "could not start the program (\(String(cString: strerror(code))))" }
    }

    /// Starts the program in a process group of its own, with its output on
    /// a pipe and its input and errors on /dev/null. Returns its pid and the
    /// pipe's read end.
    static func spawn(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> (pid_t, Int32) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw SpawnError(code: errno) }
        let (reader, writer) = (fds[0], fds[1])
        // Not inherited by programs other threads start meanwhile.
        _ = fcntl(reader, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writer, F_SETFD, FD_CLOEXEC)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writer, 1)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setpgroup(&attributes, 0)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)
        var all = sigset_t()
        sigfillset(&all)
        sigdelset(&all, SIGKILL)
        sigdelset(&all, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &all)
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(writer)
        guard result == 0 else {
            close(reader)
            throw SpawnError(code: result)
        }
        return (pid, reader)
    }
}
