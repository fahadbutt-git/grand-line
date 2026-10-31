import Foundation
import LaunchKit

/// A window to show for a file-viewer request (R19).
public struct WindowRequest: Equatable, Sendable {
    public let folder: URL
    public let select: [URL]

    public init(folder: URL, select: [URL] = []) {
        self.folder = folder
        self.select = select
    }
}

/// Turns what macOS hands the file viewer into windows. Each folder handed to
/// `open` gets a window; files handed to `open`, and everything revealed, show
/// in their folder, selected, one window per folder in the order given.
public enum ViewerRouting {
    public static func windows(for request: FileViewerRequest, isFolder: (URL) -> Bool) -> [WindowRequest] {
        switch request {
        case .open(let urls):
            var result: [WindowRequest] = []
            var files: [URL] = []
            for url in urls {
                if isFolder(url) { result.append(WindowRequest(folder: url)) } else { files.append(url) }
            }
            return result + grouped(files)
        case .reveal(let urls):
            return grouped(urls)
        }
    }

    static func grouped(_ urls: [URL]) -> [WindowRequest] {
        var order: [String] = []
        var byFolder: [String: [URL]] = [:]
        for url in urls {
            let folder = url.standardizedFileURL.deletingLastPathComponent().path
            if byFolder[folder] == nil { order.append(folder) }
            byFolder[folder, default: []].append(url)
        }
        return order.map { WindowRequest(folder: URL(fileURLWithPath: $0, isDirectory: true), select: byFolder[$0] ?? []) }
    }
}
