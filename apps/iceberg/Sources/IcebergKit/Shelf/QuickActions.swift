import Foundation

/// A name for a new file beside an existing one that is never already
/// taken: "photo-compressed.jpg", then "photo-compressed 2.jpg" and so on.
/// Quick actions only ever write to a name from here, so an original (or
/// any other file) is never overwritten.
public enum OutputName {
    /// The last number tried before giving up.
    public static let maxAttempts = 9999

    /// `suffix` is joined to the base name with a hyphen ("compressed"),
    /// or nil for none; `ext` is the new extension without the dot. A folder
    /// source keeps its whole name as the base ("Photos" gives "Photos.zip").
    public static func unique(for source: URL, suffix: String?, ext: String, isDirectory: Bool = false,
                              exists: (URL) -> Bool) -> URL? {
        let folder = source.deletingLastPathComponent()
        var base = isDirectory ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        if base.isEmpty { base = source.lastPathComponent.isEmpty ? "File" : source.lastPathComponent }
        if let suffix, !suffix.isEmpty { base += "-" + suffix }
        let dotExt = ext.isEmpty ? "" : "." + ext
        let sourcePath = source.standardizedFileURL.path
        for n in 1...maxAttempts {
            let name = n == 1 ? base + dotExt : "\(base) \(n)\(dotExt)"
            let candidate = folder.appendingPathComponent(name)
            if candidate.standardizedFileURL.path == sourcePath { continue }
            if !exists(candidate) { return candidate }
        }
        return nil
    }
}

/// Image formats the quick actions write, through `sips`.
public enum ImageFormat: String, CaseIterable, Sendable, Equatable {
    case png, jpeg, heic, tiff

    /// The extension a new file gets.
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    /// The name `sips -s format` takes.
    public var sipsName: String { rawValue }

    public var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    /// The format of a file, by its extension.
    public static func of(_ url: URL) -> ImageFormat? {
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        default: return nil
        }
    }
}

/// Which files count as images for the image actions.
public enum ImageFiles {
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    public static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// What can be done to a file on the shelf. Every action makes a new file
/// beside the original, with a name that is not taken; none changes,
/// moves or deletes the original.
public enum QuickAction: Equatable, Sendable, Hashable {
    /// A .zip of the file or folder (`ditto`, as Finder's Compress does).
    case zip
    /// A smaller copy of an image: JPEG and HEIC stay in their format at a
    /// lower quality; other images become JPEG.
    case compress
    /// A copy in another image format.
    case convert(ImageFormat)
    /// A PNG of the image with its background made transparent (Vision,
    /// on this Mac).
    case removeBackground

    public var title: String {
        switch self {
        case .zip: return "Compress to Zip"
        case .compress: return "Make a Smaller Copy"
        case .convert(let f): return "Convert to \(f.title)"
        case .removeBackground: return "Remove Background"
        }
    }

    public var symbol: String {
        switch self {
        case .zip: return "doc.zipper"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .convert: return "photo.on.rectangle"
        case .removeBackground: return "person.and.background.dotted"
        }
    }

    /// The actions offered for a file: zip for anything, the image actions
    /// for images (converting only to the formats it is not in already).
    public static func available(for url: URL, isDirectory: Bool) -> [QuickAction] {
        guard !isDirectory, ImageFiles.isImage(url) else { return [.zip] }
        let own = ImageFormat.of(url)
        var actions: [QuickAction] = [.zip, .compress]
        for format in ImageFormat.allCases where format != own { actions.append(.convert(format)) }
        actions.append(.removeBackground)
        return actions
    }

    /// The suffix and extension of the new file.
    public func output(for source: URL, isDirectory: Bool) -> (suffix: String?, ext: String) {
        switch self {
        case .zip: return (nil, "zip")
        case .compress:
            let own = ImageFormat.of(source)
            let kept: ImageFormat = (own == .jpeg || own == .heic) ? own! : .jpeg
            let ext = kept == own ? source.pathExtension.lowercased() : kept.fileExtension
            return ("compressed", ext)
        case .convert(let f): return (nil, f.fileExtension)
        case .removeBackground: return ("cutout", "png")
        }
    }

    /// Where the new file goes: beside the source, with a free name.
    public func destination(for source: URL, isDirectory: Bool, exists: (URL) -> Bool) -> URL? {
        let o = output(for: source, isDirectory: isDirectory)
        return OutputName.unique(for: source, suffix: o.suffix, ext: o.ext, isDirectory: isDirectory, exists: exists)
    }
}

/// A program and its arguments, run without a shell (so no name needs quoting).
public struct ToolInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    /// The new file it makes.
    public var output: URL

    public init(executable: String, arguments: [String], output: URL) {
        self.executable = executable
        self.arguments = arguments
        self.output = output
    }
}

public enum QuickActionPlan {
    /// JPEG and HEIC quality for a smaller copy, in percent.
    public static let compressQuality = 70

    /// The command for an action, or nil for one done in the app itself
    /// (background removal) or when no free name is left.
    public static func invocation(_ action: QuickAction, source: URL, isDirectory: Bool,
                                  exists: (URL) -> Bool) -> ToolInvocation? {
        guard let out = action.destination(for: source, isDirectory: isDirectory, exists: exists) else { return nil }
        switch action {
        case .zip:
            // Finder's Compress: the item itself inside the archive, no resource-fork clutter.
            return ToolInvocation(executable: "/usr/bin/ditto",
                                  arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, out.path],
                                  output: out)
        case .compress:
            let own = ImageFormat.of(source)
            let format: ImageFormat = (own == .jpeg || own == .heic) ? own! : .jpeg
            return ToolInvocation(executable: "/usr/bin/sips",
                                  arguments: ["-s", "format", format.sipsName, "-s", "formatOptions", String(compressQuality),
                                              source.path, "--out", out.path],
                                  output: out)
        case .convert(let format):
            return ToolInvocation(executable: "/usr/bin/sips",
                                  arguments: ["-s", "format", format.sipsName, source.path, "--out", out.path],
                                  output: out)
        case .removeBackground:
            return nil
        }
    }
}

#if canImport(Darwin)
/// Runs a tool and reports whether it made its file. At most `timeout`
/// seconds; a tool still running then is stopped.
public enum ToolRunner {
    public static func run(_ invocation: ToolInvocation, timeout: TimeInterval = 120,
                           completion: @escaping @Sendable (Result<URL, ToolError>) -> Void) {
        // The name was free when it was chosen; if it has been taken since, stop.
        if FileManager.default.fileExists(atPath: invocation.output.path) {
            completion(.failure(.outputExists))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let finished = OnceFlag()
        process.terminationHandler = { p in
            guard finished.set() else { return }
            let message = String(data: errors.fileHandleForReading.availableData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if p.terminationStatus == 0, FileManager.default.fileExists(atPath: invocation.output.path) {
                completion(.success(invocation.output))
            } else {
                completion(.failure(.failed(status: p.terminationStatus, message: String(message.prefix(300)))))
            }
        }
        do {
            try process.run()
        } catch {
            _ = finished.set()
            completion(.failure(.couldNotStart(error.localizedDescription)))
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning, finished.set() else { return }
            process.terminate()
            completion(.failure(.timedOut))
        }
    }
}

public enum ToolError: Error, Equatable, Sendable, CustomStringConvertible {
    case outputExists
    case couldNotStart(String)
    case failed(status: Int32, message: String)
    case timedOut
    case noFreeName
    case unsupported(String)

    public var description: String {
        switch self {
        case .outputExists: return "a file with the new name appeared meanwhile; nothing was written"
        case .couldNotStart(let why): return "could not start: \(why)"
        case .failed(let status, let message): return message.isEmpty ? "stopped with status \(status)" : message
        case .timedOut: return "took too long and was stopped"
        case .noFreeName: return "no free name was left beside the file"
        case .unsupported(let why): return why
        }
    }
}

/// True for the first caller only, from any thread.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
#endif
