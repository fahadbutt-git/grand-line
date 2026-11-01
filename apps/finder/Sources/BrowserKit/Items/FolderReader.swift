import FileKit
import Foundation

/// Lists a folder the way a pane shows it. `.DS_Store` and `._` files are never
/// shown (R11); other hidden files only when asked (Cmd+Shift+.).
public enum FolderReader {
    /// Stops with CancellationError when the task reading it is cancelled
    /// (the pane moved on, or a newer read replaced this one).
    public static func items(in folder: URL, showHidden: Bool) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(FileItem.keys), options: []
        )
        try Task.checkCancellation()
        var read = 0
        return try urls.compactMap { url -> FileItem? in
            read += 1
            if read & 511 == 0 { try Task.checkCancellation() }
            guard let item = FileItem.read(url) else { return nil }
            return isVisible(item.name, isHidden: item.isHidden, showHidden: showHidden) ? item : nil
        }
    }

    /// Names of the visible subfolders, for path completion and project lists.
    public static func subfolderNames(_ folder: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values?.isDirectory == true && values?.isPackage != true ? url.lastPathComponent : nil
        }
    }

    public static func isVisible(_ name: String, isHidden: Bool, showHidden: Bool) -> Bool {
        if Clutter.isClutter(name) { return false }
        return showHidden || !isHidden
    }
}
