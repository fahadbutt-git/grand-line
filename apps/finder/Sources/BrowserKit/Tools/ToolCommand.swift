import Foundation

/// A program to run for one of the package's tools (R31, R33).
public struct ToolCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]

    public init(_ executable: String, _ arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// Ctrl+Option+T: a new Ghostty window in the folder.
    public static func terminal(at folder: URL) -> ToolCommand {
        ToolCommand("/usr/bin/open", ["-na", "Ghostty", "--args", "--working-directory=" + folder.path])
    }

    /// Ctrl+Option+A: Claude Code in a new Ghostty window in the folder.
    public static func claude(at folder: URL) -> ToolCommand {
        ToolCommand("/usr/bin/open", ["-na", "Ghostty", "--args", "--working-directory=" + folder.path, "-e", "claude"])
    }

    public static func transcode(_ mode: TranscodeMode, _ files: [URL], script: URL) -> ToolCommand {
        ToolCommand(script.path, [mode.rawValue] + files.map(\.path))
    }

    /// Connect to Server: macOS mounts smb://, afp://, nfs://, ftp:// and webdav
    /// addresses itself and puts the share under /Volumes.
    public static func connect(to address: String) -> ToolCommand? {
        guard let url = ServerAddress.normalize(address) else { return nil }
        return ToolCommand("/usr/bin/open", [url.absoluteString])
    }

    /// The folder the terminal and Claude open in: the pane's folder, or the
    /// folder of a single selected folder.
    public static func workingFolder(pane: URL?, selection: [FileItem]) -> URL? {
        if selection.count == 1, selection[0].isFolder, !selection[0].isInArchive { return selection[0].url }
        return pane
    }
}

/// The modes of ~/.grand-line/bin/transcode, and the files each one takes.
public enum TranscodeMode: String, CaseIterable, Sendable {
    case video, png, jpeg, pdf, text

    public var command: BrowserCommand {
        switch self {
        case .video: return .transcodeVideo
        case .png: return .transcodePNG
        case .jpeg: return .transcodeJPEG
        case .pdf: return .transcodePDF
        case .text: return .transcodeText
        }
    }

    public static func mode(for command: BrowserCommand) -> TranscodeMode? {
        allCases.first { $0.command == command }
    }

    public var extensions: Set<String> {
        switch self {
        case .video: return ["mp4", "mov", "m4v", "mkv", "avi"]
        case .png, .jpeg: return ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]
        case .pdf: return ["pdf"]
        case .text: return ["pdf", "doc", "docx", "rtf", "odt", "html", "htm"]
        }
    }

    /// Shown when every selected file fits the mode.
    public func accepts(_ items: [FileItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { !$0.isFolder && !$0.isInArchive && extensions.contains($0.ext) }
    }
}

/// What Connect to Server accepts: "smb://nas/share", or a bare host, which means SMB.
public enum ServerAddress {
    static let schemes: Set<String> = ["smb", "afp", "nfs", "ftp", "http", "https", "vnc", "cifs"]

    public static func normalize(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "smb://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
