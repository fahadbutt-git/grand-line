import Foundation

/// A Google Drive for desktop account, mounted by File Provider at
/// ~/Library/CloudStorage/GoogleDrive-<account>.
public struct GoogleDrive: Sendable, Equatable {
    public let root: URL
    public let account: String

    public var myDrive: URL { root.appendingPathComponent("My Drive", isDirectory: true) }
    public var sharedDrives: URL { root.appendingPathComponent("Shared drives", isDirectory: true) }

    public static let folderPrefix = "GoogleDrive-"

    public enum DragOperation: Sendable, Equatable {
        case copy
        case move
    }

    public static func accounts(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [GoogleDrive] {
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: storage.path)) ?? []
        return names
            .filter { $0.hasPrefix(folderPrefix) && $0.count > folderPrefix.count }
            .sorted()
            .map { GoogleDrive(root: storage.appendingPathComponent($0, isDirectory: true), account: String($0.dropFirst(folderPrefix.count))) }
    }

    /// True for the drive's root and anything inside it, including through links such as ~/Drive.
    public func contains(_ url: URL) -> Bool {
        let path = Self.resolved(url)
        let base = Self.resolved(root)
        return path == base || path.hasPrefix(base + "/")
    }

    public static func drive(containing url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> GoogleDrive? {
        accounts(home: home).first { $0.contains(url) }
    }

    /// Finder's default for a drag without modifier keys, with one change: dragging
    /// out of Google Drive copies, so a file is never pulled out of the cloud by accident.
    /// Otherwise items move within a volume and copy across volumes.
    public static func dragOperation(
        from sources: [URL],
        to destination: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DragOperation {
        let drives = accounts(home: home)
        let target = drives.first { $0.contains(destination) }
        for source in sources {
            if let drive = drives.first(where: { $0.contains(source) }), drive != target { return .copy }
            if !sameVolume(source, destination) { return .copy }
        }
        return .move
    }

    static func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let first = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let second = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let first, let second else { return true }
        return first.isEqual(second)
    }
}
