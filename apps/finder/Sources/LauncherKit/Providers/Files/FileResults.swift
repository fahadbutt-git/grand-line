import Foundation
import IndexKit

/// A file found by the name index or by Spotlight.
public struct FileHit: Sendable, Equatable {
    public let path: String
    public let isFolder: Bool
    public let modified: Date?
    public let tier: MatchTier
    public let highlights: [Range<Int>]

    public init(path: String, isFolder: Bool, modified: Date? = nil, tier: MatchTier = .substring, highlights: [Range<Int>] = []) {
        self.path = path
        self.isFolder = isFolder
        self.modified = modified
        self.tier = tier
        self.highlights = highlights
    }

    public init(_ match: IndexMatch) {
        self.init(path: match.path, isFolder: match.isFolder, tier: match.tier, highlights: match.highlights)
    }

    public var name: String { (path as NSString).lastPathComponent }
    public var ext: String { (path as NSString).pathExtension.lowercased() }
}

/// Rows for files, with every file action: open (folders in Nexus), show in
/// Nexus, Quick Look, open with, copy path or file, move, AirDrop, transcode.
public enum FileResults {
    /// System Settings › Privacy & Security › Files and Folders.
    public static let filesAndFoldersPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

    /// A row for each folder macOS would not let the name index read, so missing
    /// files are explained instead of silently absent: folders right in the home
    /// folder (Desktop, Documents, Downloads) and Google Drive's folders.
    public static func permissionRows(_ folders: [String], home: String) -> [LaunchResult] {
        let homes = Set([home, FolderWatcher.realPath(home)])
        var rows: [LaunchResult] = []
        for folder in folders {
            let parent = (folder as NSString).deletingLastPathComponent
            let name: String
            if homes.contains(parent) {
                name = (folder as NSString).lastPathComponent
            } else if homes.contains(where: { FolderChange.isInside(folder, $0 + "/Library/CloudStorage") }) {
                name = "Google Drive"
            } else {
                continue
            }
            if rows.contains(where: { $0.title.hasSuffix(" " + name) }) { continue }
            rows.append(LaunchResult(
                id: "allow:" + folder,
                title: "Allow Sight to read " + name,
                subtitle: "macOS is keeping Sight out of \(name), so its files are missing here",
                icon: .symbol("lock"),
                section: .files,
                actions: [LaunchAction("Open Privacy Settings", symbol: "gear", .openURL(filesAndFoldersPane, bundleID: nil))],
                isFallback: true,
                providerID: "files"
            ))
        }
        return rows
    }

    public static func symbol(for hit: FileHit) -> String {
        if hit.isFolder { return "folder" }
        switch hit.ext {
        case "app": return "app"
        case "pdf": return "doc.richtext"
        case "doc", "docx", "odt", "rtf", "pages": return "doc.text"
        case "xls", "xlsx", "ods", "numbers", "csv", "tsv": return "tablecells"
        case "ppt", "pptx", "odp", "key": return "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "svg": return "photo"
        case "mov", "mp4", "m4v", "mkv", "avi": return "film"
        case "mp3", "m4a", "wav", "aiff", "flac": return "waveform"
        case "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz": return "doc.zipper"
        case "md", "txt": return "doc.plaintext"
        case "r", "py", "swift", "js", "ts", "sh", "c", "h", "m", "json", "yml", "yaml", "toml": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }

    /// The transcode modes that make sense for a file, as bin/transcode names them.
    public static func transcodeModes(_ ext: String) -> [String] {
        switch ext {
        case "mov", "mp4", "m4v", "mkv", "avi": return ["video"]
        case "png": return ["jpeg"]
        case "jpg", "jpeg": return ["png"]
        case "heic", "tif", "tiff", "gif", "webp", "bmp": return ["png", "jpeg"]
        case "pdf": return ["pdf", "text"]
        case "doc", "docx": return ["text"]
        default: return []
        }
    }

    /// "…/Research/Cornea": the last two folders above the file.
    public static func shortFolder(_ path: String, paths: GrandLinePaths) -> String {
        let folder = paths.abbreviate((path as NSString).deletingLastPathComponent)
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 3 else { return folder }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    public static func actions(_ hit: FileHit, paths: GrandLinePaths) -> [LaunchAction] {
        let path = hit.path
        var actions: [LaunchAction] = [
            LaunchAction(hit.isFolder ? "Open in Nexus" : "Open", symbol: "arrow.up.forward", .open(path)),
            LaunchAction("Show in Nexus", symbol: "folder", .reveal(path)),
            LaunchAction("Quick Look", symbol: "eye", shortcut: KeyShortcut("y"), closesWindow: false, .quickLook(path)),
        ]
        if !hit.isFolder { actions.append(LaunchAction("Open with…", symbol: "arrow.up.right.square", shortcut: KeyShortcut("o"), .openWith(path))) }
        actions += [
            LaunchAction("Copy path", symbol: "doc.on.clipboard", shortcut: KeyShortcut("c", option: true), .copyText(path)),
            LaunchAction("Copy file", symbol: "doc.on.doc", shortcut: KeyShortcut("c", shift: true), .copyFile(path)),
            LaunchAction("Move to…", symbol: "folder.badge.plus", shortcut: KeyShortcut("m", shift: true), .moveTo(path)),
            LaunchAction("AirDrop", symbol: "airplayaudio", .airDrop(path)),
        ]
        for mode in transcodeModes(hit.ext) {
            actions.append(LaunchAction("Transcode: \(mode)", symbol: "arrow.triangle.2.circlepath", .run(paths.command("transcode"), arguments: [mode, path])))
        }
        actions.append(.favourite)
        return actions
    }

    public static func result(_ hit: FileHit, paths: GrandLinePaths, now: Date = Date()) -> LaunchResult {
        LaunchResult(
            id: "file:" + hit.path,
            title: hit.name,
            subtitle: shortFolder(hit.path, paths: paths),
            icon: .symbol(symbol(for: hit)),
            section: hit.ext == "app" ? .apps : .files,
            accessory: hit.modified.map { DateText.relative($0, now: now) } ?? (hit.isFolder ? "Folder" : ""),
            actions: actions(hit, paths: paths),
            previewPath: hit.path,
            providerID: "files",
            match: MatchInfo(title: hit.tier, highlights: hit.highlights)
        )
    }
}
