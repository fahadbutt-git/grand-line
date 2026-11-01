import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// What came back from one run of a widget command.
public struct CommandResult: Equatable, Sendable {
    public var stdout: String = ""
    public var stderr: String = ""
    /// The exit status, when the command ended by itself.
    public var exitCode: Int32?
    /// The signal that ended it, when one did.
    public var signal: Int32?
    /// True when it was stopped for running longer than `timeout`.
    public var timedOut = false
    public var timeout: TimeInterval = 0
    public var duration: TimeInterval = 0
    /// True when output beyond `maxOutputBytes` was dropped.
    public var truncated = false
    /// Set when the command could not be started at all.
    public var launchError: String?

    public init() {}
}

/// Runs one shell command with a hard time limit.
///
/// The command runs in its own process group (`/bin/sh -c`), so when it hangs
/// the whole group, including anything it started, gets SIGTERM and then
/// SIGKILL. When it ends by itself, whatever it left running in the group
/// (`helper &`) is killed too, so repeated runs cannot pile up orphans; a
/// helper meant to outlive the run must leave the group (`open`, launchd, or
/// a new session). Output is read as it arrives and capped, so a chatty command
/// cannot fill memory. This is the technique SketchyBar uses (a fork with an
/// alarm), done with posix_spawn so it is safe from a multithreaded app.
public struct CommandRunner: Sendable {
    public var shell = "/bin/sh"
    public var environment: [String: String]
    public var maxOutputBytes = 64 * 1024
    /// How long a stopped command gets between SIGTERM and SIGKILL.
    public var killGrace: TimeInterval = 0.5

    public init(environment: [String: String] = CommandRunner.defaultEnvironment()) {
        self.environment = environment
    }

    /// The app's environment with the package's tools on the PATH. Apps opened
    /// from Finder get only /usr/bin:/bin:/usr/sbin:/sbin, which would hide
    /// Homebrew and `~/.grand-line/bin` from widget commands.
    public static func defaultEnvironment(home: String = NSHomeDirectory(),
                                          base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let extra = ["\(home)/.grand-line/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let existing = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var path: [String] = []
        for p in extra + existing where !path.contains(p) { path.append(p) }
        env["PATH"] = path.joined(separator: ":")
        env["HOME"] = env["HOME"] ?? home
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }

    /// Runs `command` with `/bin/sh`, in `workingDirectory` when given, and
    /// returns within roughly `timeout + killGrace` seconds whatever it does.
    public func run(_ command: String, timeout: TimeInterval, workingDirectory: URL? = nil,
                    extraEnvironment: [String: String] = [:]) -> CommandResult {
        var result = CommandResult()
        result.timeout = timeout
        let started = Date()

        // `cd` first, then `eval` the command, so a missing folder is reported
        // and the command itself is run exactly as written.
        let script = "cd \"$1\" 2>/dev/null || { echo \"Iceberg: folder $1 is missing\" >&2; exit 126; }; shift; eval \"$1\""
        let directory = workingDirectory?.path ?? NSHomeDirectory()
        let args = [shell, "-c", script, "iceberg", directory, command]

        var env = environment
        for (k, v) in extraEnvironment { env[k] = v }
        let envList = env.map { "\($0.key)=\($0.value)" }

        var outPipe: [Int32] = [-1, -1]
        var errPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else {
            result.launchError = "Could not start (no pipe)"
            return result
        }
        guard pipe(&errPipe) == 0 else {
            close(outPipe[0]); close(outPipe[1])
            result.launchError = "Could not start (no pipe)"
            return result
        }
        // Keep these out of every other process this app starts.
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
            result.launchError = "Could not start \(shell) (\(String(cString: strerror(spawned))))"
            return result
        }

        let deadline = started.addingTimeInterval(timeout)
        var out = [UInt8]()
        var err = [UInt8]()
        var openFds: [Int32] = [outPipe[0], errPipe[0]]
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var status: Int32 = 0
        var exited = false
        var exitedAt: Date?

        func reap(_ options: Int32) -> Bool {
            while true {
                let r = waitpid(pid, &status, options)
                if r == pid { return true }
                if r == -1 && errno == EINTR { continue }
                return false
            }
        }

        while !openFds.isEmpty {
            let now = Date()
            if !exited, reap(WNOHANG) { exited = true; exitedAt = now }
            // A background child can keep the pipe open after the command
            // ended; stop listening shortly after the command itself is gone.
            if let at = exitedAt, now.timeIntervalSince(at) > 0.2 { break }
            if now >= deadline { break }
            let wait = min(deadline.timeIntervalSince(now), 0.1)
            var fds = openFds.map { pollfd(fd: $0, events: Int16(POLLIN), revents: 0) }
            let fdCount = nfds_t(fds.count)
            let ready = poll(&fds, fdCount, Int32(max(1, wait * 1000)))
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }
            for p in fds where p.revents != 0 {
                let n = read(p.fd, &buffer, bufferSize)
                if n > 0 {
                    let isOut = p.fd == outPipe[0]
                    let room = maxOutputBytes - (isOut ? out.count : err.count)
                    if room > 0 {
                        let take = min(room, n)
                        if isOut { out.append(contentsOf: buffer[0..<take]) } else { err.append(contentsOf: buffer[0..<take]) }
                    }
                    if n > room { result.truncated = true }
                } else if n == 0 || (errno != EINTR && errno != EAGAIN) {
                    close(p.fd)
                    openFds.removeAll { $0 == p.fd }
                }
            }
        }
        for fd in openFds { close(fd) }

        // The output may have closed before the command ended: wait for it
        // until the deadline.
        while !exited && Date() < deadline {
            if reap(WNOHANG) { exited = true; break }
            usleep(20_000)
        }
        if !exited {
            result.timedOut = true
            signalGroup(pid, SIGTERM)
            let graceEnd = Date().addingTimeInterval(killGrace)
            while Date() < graceEnd {
                if reap(WNOHANG) { exited = true; break }
                usleep(10_000)
            }
            if !exited {
                signalGroup(pid, SIGKILL)
                _ = reap(0)
            }
        }
        // The leader is reaped now. Anything it left behind in its group goes
        // too, whether it timed out or ended normally; the group only, as the
        // bare pid may already belong to another process.
        ProcessGroup.signal(pid, SIGKILL, leaderReaped: true)

        let low = status & 0x7f
        if low == 0 {
            result.exitCode = (status >> 8) & 0xff
        } else if low != 0x7f {
            result.signal = low
        }
        result.stdout = String(decoding: out, as: UTF8.self)
        result.stderr = String(decoding: err, as: UTF8.self)
        result.duration = Date().timeIntervalSince(started)
        return result
    }

    /// Before the leader is reaped (it is still our child, so its pid cannot
    /// have been reused).
    private func signalGroup(_ pid: pid_t, _ sig: Int32) {
        ProcessGroup.signal(pid, sig, leaderReaped: false)
    }
}

/// Signals a command's process group (its leader's pid is the group's id).
public enum ProcessGroup {
    /// Sends `sig` to the group `pid` leads. Only while the leader is not yet
    /// reaped (`leaderReaped` false) may it fall back to the bare pid: after
    /// waitpid the pid is free and may belong to an unrelated process. The
    /// group id itself cannot be handed out again while any member lives.
    /// Returns true when a signal was delivered.
    @discardableResult
    public static func signal(_ pid: pid_t, _ sig: Int32, leaderReaped: Bool) -> Bool {
        guard pid > 0 else { return false }
        if kill(-pid, sig) == 0 { return true }
        guard !leaderReaped else { return false }
        return kill(pid, sig) == 0
    }
}
