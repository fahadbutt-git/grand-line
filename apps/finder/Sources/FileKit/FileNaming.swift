import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Finder's names for copies: "Report 2.pdf" when keeping both, "Report copy.pdf"
/// for Duplicate, "untitled folder 2" for a second new folder.
public enum FileNaming {
    /// The first free name in `folder` for keeping both: name, then "name 2", "name 3".
    /// Names in `avoiding` count as taken, for several items going to one folder.
    /// They are compared without case, as the Mac's volumes compare names.
    public static func keepBoth(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        let taken = folded(avoiding)
        let (stem, ext) = split(name)
        let base = stripNumber(stem)
        var number = 2
        while true {
            let candidate = join("\(base) \(number)", ext)
            if !taken.contains(key(candidate)), !exists(candidate, in: folder) { return candidate }
            number += 1
        }
    }

    /// The first free name for Duplicate: "name copy", then "name copy 2".
    public static func duplicate(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        let taken = folded(avoiding)
        let (stem, ext) = split(name)
        let first = join("\(stem) copy", ext)
        if !taken.contains(key(first)), !exists(first, in: folder) { return first }
        var number = 2
        while true {
            let candidate = join("\(stem) copy \(number)", ext)
            if !taken.contains(key(candidate)), !exists(candidate, in: folder) { return candidate }
            number += 1
        }
    }

    /// `name` itself when free, otherwise the keep-both name.
    public static func available(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        folded(avoiding).contains(key(name)) || exists(name, in: folder) ? keepBoth(name, in: folder, avoiding: avoiding) : name
    }

    /// The key names are compared by.
    static func key(_ name: String) -> String {
        FileIdentity.nameKey(name)
    }

    static func folded(_ names: Set<String>) -> Set<String> {
        Set(names.map(key))
    }

    /// Whether a name can be used for a file.
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
            && name.utf8.count <= 255
    }

    static func split(_ name: String) -> (String, String) {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        if ext.isEmpty || stem.isEmpty || ext.contains(" ") { return (name, "") }
        return (stem, ext)
    }

    static func join(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : stem + "." + ext
    }

    /// "Report 2" becomes "Report", so keeping both again gives "Report 3", not "Report 2 2".
    static func stripNumber(_ stem: String) -> String {
        guard let space = stem.lastIndex(of: " ") else { return stem }
        let digits = stem[stem.index(after: space)...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), space != stem.startIndex else {
            return stem
        }
        return String(stem[..<space])
    }

    static func exists(_ name: String, in folder: URL) -> Bool {
        var isFolder: ObjCBool = false
        let path = folder.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }

    // MARK: Claiming a name

    /// Claims a free name in `folder` at the moment of the call: an empty file
    /// is made there with O_CREAT | O_EXCL, which fails rather than open
    /// anything already there, so two tasks (or another app) can never be
    /// handed one name. `name` first, then "name 2", "name 3". The caller
    /// writes elsewhere and `settle`s onto the name, or `release`s it.
    public static func reserve(_ name: String, in folder: URL) throws -> ReservedName {
        guard isValid(name) else { throw FileOperationError.invalidName(name) }
        let (stem, ext) = split(name)
        let base = stripNumber(stem)
        var candidate = name
        var number = 1
        while number < 100_000 {
            let url = folder.appendingPathComponent(candidate)
            var failure: Int32 = 0
            let stamp = url.withUnsafeFileSystemRepresentation { path -> FileStamp? in
                guard let path else { failure = ENOENT; return nil }
                let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
                guard fd >= 0 else { failure = errno; return nil }
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0 else { failure = errno; return nil }
                return FileStamp(device: Int64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino))
            }
            if let stamp { return ReservedName(url: url, stamp: stamp) }
            guard failure == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
            }
            number += 1
            candidate = join("\(base) \(number)", ext)
        }
        throw FileOperationError.nameTaken(name)
    }

    /// Puts `made` (an item Nexus wrote beside the reserved name) in the
    /// reserved name's place, in one rename over the empty file `reserve`
    /// left there. Throws, and leaves both alone, when that file is no longer
    /// the one `reserve` made.
    public static func settle(_ made: URL, onto reserved: ReservedName) throws {
        guard reserved.isUntouched else { throw FileOperationError.nameTaken(reserved.url.lastPathComponent) }
        let status = made.withUnsafeFileSystemRepresentation { from -> Int32 in
            reserved.url.withUnsafeFileSystemRepresentation { to -> Int32 in
                guard let from, let to else { return -1 }
                return rename(from, to)
            }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

/// A name claimed by `FileNaming.reserve`: an empty file Nexus made itself.
public struct ReservedName: Sendable, Equatable {
    public let url: URL
    public let stamp: FileStamp

    /// Still the empty file `reserve` made, so it holds nothing of anyone's.
    public var isUntouched: Bool {
        guard let info = FileStamp.info(url, followingLink: false) else { return false }
        let now = FileStamp(device: Int64(truncatingIfNeeded: info.st_dev), inode: UInt64(info.st_ino))
        return now == stamp && info.st_size == 0
    }

    /// Gives the name back: the empty file goes, but only while it is still
    /// the untouched one made by `reserve`; anything else is left alone.
    public func release() {
        guard isUntouched else { return }
        _ = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return unlink(path)
        }
    }
}
