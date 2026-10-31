import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// How a stream widget's command ended.
public struct StreamExit: Equatable, Sendable {
    public var exitCode: Int32?
    public var signal: Int32?
    public var duration: TimeInterval = 0
    /// The end of what it wrote to stderr, for the diagnostics.
    public var stderrTail = ""
    /// True when Iceberg stopped it (the panel closed, sleep, a reload).
    public var stoppedByRequest = false
    public var launchError: String?
    /// How many lines it printed.
    public var lines = 0

    public init() {}

    /// True when it ended by itself in a way that counts as a failure. A
    /// stream is meant to keep running, so ending at all, even with status 0,
    /// is a failure unless it was asked to stop.
    public var isFailure: Bool { !stoppedByRequest }

    /// One line on why it ended.
    public var reason: String {
        if let launchError { return launchError }
        if stoppedByRequest { return "Stopped" }
        let tail = stderrTail.split(whereSeparator: { $0.isNewline }).last.map { CommandOutputParser.clean(String($0)) } ?? ""
        let how = exitCode.map { "exit \($0)" } ?? signal.map { "signal \($0)" } ?? "ended"
        return tail.isEmpty ? "The stream ended (\(how))" : "\(tail) (\(how))"
    }
}

/// Runs a stream widget's command: a long-running script that prints one
/// line per update (Waybar's continuous mode, eww's `deflisten`).
///
/// Like `CommandRunner`, the command runs with `/bin/sh` in its own process
/// group, so stopping it stops everything it started. Lines are handed on
/// at most once every `minimumInterval`; a script that prints faster only
/// has its newest line shown, so a busy script cannot flood the panel.
public final class StreamProcess: @unchecked Sendable {
    public let command: String
    public var shell = "/bin/sh"
    public var minimumInterval: TimeInterval = 0.1
    public var maxLineBytes = 64 * 1024
    public var killGrace: TimeInterval = 0.5

    private let workingDirectory: URL?
    private let environment: [String: String]
    private let lock = NSLock()
    private var pid: pid_t = 0
    private var started = false
    private var finished = false
    private var stopRequested = false

    public init(command: String, workingDirectory: URL? = nil,
                environment: [String: String] = CommandRunner.defaultEnvironment()) {
        self.command = command
        self.workingDirectory = workingDirectory
        var env = environment
        // Python and others buffer their output when it is not a terminal,
        // which makes a stream look frozen.
        env["PYTHONUNBUFFERED"] = "1"
        self.environment = env
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public var isRunning: Bool { locked { started && !finished } }

    /// Starts the command. `onLine` gets each update and `onExit` the end,
    /// both on a background thread. Returns false when it could not start
    /// (then `onExit` has been called with the reason) or already started.
    @discardableResult
    public func start(onLine: @escaping @Sendable (String) -> Void,
                      onExit: @escaping @Sendable (StreamExit) -> Void) -> Bool {
        let first = locked { () -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard first else { return false }
        let began = Date()
        let script = "cd \"$1\" 2>/dev/null || { echo \"Iceberg: folder $1 is missing\" >&2; exit 126; }; shift; eval \"$1\""
        let directory = workingDirectory?.path ?? NSHomeDirectory()
        switch GroupSpawn.spawn(shell: shell, args: [shell, "-c", script, "iceberg", directory, command], environment: environment) {
        case .failure(let message):
            locked { finished = true }
            var exit = StreamExit()
            exit.launchError = message
            onExit(exit)
            return false
        case .success(let child):
            let stopNow = locked { () -> Bool in
                pid = child.pid
                return stopRequested
            }
            Thread.detachNewThread { [self] in
                self.read(child, began: began, onLine: onLine, onExit: onExit)
            }
            if stopNow { stop() }
            return true
        }
    }

    /// Stops the command and everything it started: SIGTERM, then SIGKILL
    /// after `killGrace` if it is still there.
    public func stop() {
        let target = locked { () -> pid_t in
            stopRequested = true
            return finished ? 0 : pid
        }
        guard target > 0 else { return }
        GroupSpawn.signalGroup(target, SIGTERM)
        let grace = killGrace
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + grace) { [self] in
            let still = self.locked { self.finished ? 0 : self.pid }
            if still > 0 { GroupSpawn.signalGroup(still, SIGKILL) }
        }
    }

    private func read(_ child: GroupSpawn.Child, began: Date,
                      onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (StreamExit) -> Void) {
        var lines = LineBuffer()
        lines.maxLineBytes = maxLineBytes
        var errTail = [UInt8]()
        var openFds = [child.stdout, child.stderr]
        var pending: String?
        var lastDelivered = Date.distantPast
        var count = 0
        var status: Int32 = 0
        var exited = false
        var exitedAt: Date?
        let chunkSize = 16 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        func reap() -> Bool {
            while true {
                let r = waitpid(child.pid, &status, WNOHANG)
                if r == child.pid { return true }
                if r == -1 && errno == EINTR { continue }
                return false
            }
        }
        func deliverPending(force: Bool) {
            guard let line = pending else { return }
            let now = Date()
            if force || now.timeIntervalSince(lastDelivered) >= minimumInterval {
                pending = nil
                lastDelivered = now
                onLine(line)
            }
        }

        while true {
            deliverPending(force: false)
            if !exited, reap() {
                exited = true
                exitedAt = Date()
                locked { finished = true }
            }
            if openFds.isEmpty { if exited { break } else { usleep(50_000); continue } }
            // Something it started in the background can keep the pipes open;
            // stop listening shortly after the command itself is gone.
            if let at = exitedAt, Date().timeIntervalSince(at) > 0.2 { break }
            var fds = openFds.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            let ready = poll(&fds, nfds_t(fds.count), 100)
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            for p in fds where p.revents != 0 {
                let n = Darwinish.read(p.fd, &chunk, chunkSize)
                if n > 0 {
                    if p.fd == child.stdout {
                        for line in lines.append(Data(chunk[0..<n])) {
                            count += 1
                            pending = line
                            deliverPending(force: false)
                        }
                    } else {
                        errTail.append(contentsOf: chunk[0..<n])
                        if errTail.count > 2048 { errTail.removeFirst(errTail.count - 2048) }
                    }
                } else if n == 0 || (errno != EINTR && errno != EAGAIN) {
                    close(p.fd)
                    openFds.removeAll { $0 == p.fd }
                }
            }
        }
        for fd in openFds { close(fd) }
        deliverPending(force: true)
        if !exited {
            while waitpid(child.pid, &status, 0) == -1 && errno == EINTR {}
        }
        // Anything it left behind in its group goes too.
        GroupSpawn.signalGroup(child.pid, SIGKILL)
        let requested = locked { () -> Bool in
            finished = true
            pid = 0
            return stopRequested
        }

        var exit = StreamExit()
        let low = status & 0x7f
        if low == 0 { exit.exitCode = (status >> 8) & 0xff } else if low != 0x7f { exit.signal = low }
        exit.duration = Date().timeIntervalSince(began)
        exit.stderrTail = String(decoding: errTail, as: UTF8.self)
        exit.stoppedByRequest = requested
        exit.lines = count
        onExit(exit)
    }
}

/// `read(2)`, named so it does not clash with `StreamProcess.read`.
enum Darwinish {
    static func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        #if canImport(Darwin)
        return Darwin.read(fd, buffer, count)
        #else
        return Glibc.read(fd, buffer, count)
        #endif
    }
}

/// Starts `/bin/sh` in a new process group with its output on pipes.
enum GroupSpawn {
    struct Child: Sendable {
        let pid: pid_t
        let stdout: Int32
        let stderr: Int32
    }

    enum Outcome {
        case success(Child)
        case failure(String)
    }

    static func spawn(shell: String, args: [String], environment: [String: String]) -> Outcome {
        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else { return .failure("Could not start (no pipe)") }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            return .failure("Could not start (no pipe)")
        }
        for fd in outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        #if canImport(Darwin)
        var actions: posix_spawn_file_actions_t? = nil
        var attrs: posix_spawnattr_t? = nil
        #else
        var actions = posix_spawn_file_actions_t()
        var attrs = posix_spawnattr_t()
        #endif
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attrs)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attrs)
        }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        var flags = Int32(POSIX_SPAWN_SETPGROUP) | Int32(POSIX_SPAWN_SETSIGMASK) | Int32(POSIX_SPAWN_SETSIGDEF)
        #if canImport(Darwin)
        flags |= Int32(POSIX_SPAWN_CLOEXEC_DEFAULT)
        #endif
        posix_spawnattr_setflags(&attrs, Int16(truncatingIfNeeded: flags))
        posix_spawnattr_setpgroup(&attrs, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attrs, &noSignals)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGPIPE)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGINT)
        posix_spawnattr_setsigdefault(&attrs, &defaultSignals)

        let envList = environment.map { "\($0.key)=\($0.value)" }
        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        let cEnv: [UnsafeMutablePointer<CChar>?] = envList.map { strdup($0) } + [nil]
        defer {
            for p in cArgs { free(p) }
            for p in cEnv { free(p) }
        }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, shell, &actions, &attrs, cArgs, cEnv)
        close(outPipe[1])
        close(errPipe[1])
        guard spawned == 0 else {
            close(outPipe[0]); close(errPipe[0])
            return .failure("Could not start \(shell) (\(String(cString: strerror(spawned))))")
        }
        return .success(Child(pid: pid, stdout: outPipe[0], stderr: errPipe[0]))
    }

    static func signalGroup(_ pid: pid_t, _ sig: Int32) {
        if kill(-pid, sig) != 0 { _ = kill(pid, sig) }
    }
}
