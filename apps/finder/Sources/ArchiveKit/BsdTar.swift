import Foundation

public enum ArchiveError: Error, Equatable {
    /// An absolute path or one with "..", which could write outside the destination.
    case unsafePath(String)
    case notInArchive(String)
    /// bsdtar failed: its exit status and message.
    case toolFailed(Int32, String)
}

/// Runs /usr/bin/bsdtar, which is libarchive and reads zip, 7z, rar and tar in all
/// its compressions.
enum BsdTar {
    static let tool = URL(fileURLWithPath: "/usr/bin/bsdtar")

    /// A UTF-8 locale prints names as they are and months in English.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        return environment
    }

    /// Runs bsdtar to the end on this thread. stdout and stderr are both
    /// read while it runs, so a long error cannot block it.
    static func run(_ arguments: [String]) throws -> Data {
        try checked(ChildProcess.runAndWait(tool.path, arguments, environment: environment))
    }

    /// Runs bsdtar as part of a task: cancelling the task stops it (and
    /// anything it started) and throws CancellationError.
    static func runCancellable(_ arguments: [String]) async throws -> Data {
        try checked(await ChildProcess.run(tool.path, arguments, environment: environment))
    }

    static func checked(_ output: ChildProcess.Output) throws -> Data {
        guard output.succeeded else {
            throw ArchiveError.toolFailed(output.status, output.errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.output
    }

    static func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    static let escapes: [UInt8: UInt8] = [
        UInt8(ascii: "\\"): 0x5C, UInt8(ascii: "a"): 0x07, UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C,
        UInt8(ascii: "n"): 0x0A, UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09, UInt8(ascii: "v"): 0x0B,
    ]

    /// bsdtar prints \\ for a backslash and \ooo or \n for unprintable bytes. Undo that.
    static func unescape(_ line: String) -> String {
        guard line.contains("\\") else { return line }
        let bytes = Array(line.utf8)
        var out: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            guard byte == UInt8(ascii: "\\"), i + 1 < bytes.count else {
                out.append(byte)
                i += 1
                continue
            }
            if let value = escapes[bytes[i + 1]] {
                out.append(value)
                i += 2
            } else if i + 3 < bytes.count,
                      bytes[(i + 1)...(i + 3)].allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "7") }) {
                let value = bytes[(i + 1)...(i + 3)].reduce(0) { $0 * 8 + Int($1 - UInt8(ascii: "0")) }
                out.append(UInt8(truncatingIfNeeded: value))
                i += 4
            } else {
                out.append(byte)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }
}
