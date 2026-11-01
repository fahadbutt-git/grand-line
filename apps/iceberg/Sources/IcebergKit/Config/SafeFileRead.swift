import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Reads a small config file without ever blocking or filling memory.
///
/// A config file can be a symlink (dotfile managers link them), so links
/// are followed, but the file reached must be a regular file: a FIFO would
/// block the read forever and `/dev/zero` would never end. It is opened
/// non-blocking (a FIFO's open does not wait for a writer), checked with
/// fstat on the open descriptor (no race with a swap in between), and at
/// most `limit` bytes are read.
public enum SafeFileRead {
    public enum Failure: Error, Equatable, Sendable {
        case missing
        case notAFile
        case tooLarge
        case unreadable(String)
    }

    public static func read(_ url: URL, limit: Int) -> Result<Data, Failure> {
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            let e = errno
            return .failure(e == ENOENT || e == ENOTDIR ? .missing : .unreadable(String(cString: strerror(e))))
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return .failure(.unreadable(String(cString: strerror(errno)))) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return .failure(.notAFile) }
        guard Int64(info.st_size) <= Int64(limit) else { return .failure(.tooLarge) }
        // Back to blocking for a regular file (reads of one never wait long).
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwinish.read(fd, $0.baseAddress!, $0.count) }
            if n > 0 {
                out.append(contentsOf: buffer[0..<n])
                // It grew while being read: refuse it rather than read on.
                if out.count > limit { return .failure(.tooLarge) }
            } else if n == 0 {
                return .success(out)
            } else if errno == EINTR {
                continue
            } else {
                return .failure(.unreadable(String(cString: strerror(errno))))
            }
        }
    }
}
