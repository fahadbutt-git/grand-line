import FileKit
import Foundation

/// Where a search looks (R3). It starts in the current folder; the chips widen
/// it to the home folder, Google Drive, then the whole Mac.
public enum SearchScope: Hashable, Codable, Sendable {
    case folder(String)
    case home
    case drive
    case mac

    /// The chips beside the search field, narrowest first.
    public static func chips(from folder: String?) -> [SearchScope] {
        (folder.map { [SearchScope.folder($0)] } ?? []) + [.home, .drive, .mac]
    }

    public var title: String {
        switch self {
        case .folder(let path): return (path as NSString).lastPathComponent.isEmpty ? "/" : (path as NSString).lastPathComponent
        case .home: return "Home"
        case .drive: return "Drive"
        case .mac: return "This Mac"
        }
    }

    public var symbol: String {
        switch self {
        case .folder: return "folder"
        case .home: return "house"
        case .drive: return "externaldrive.connected.to.line.below"
        case .mac: return "desktopcomputer"
        }
    }

    /// The next wider scope, nil at the whole Mac.
    public var wider: SearchScope? {
        switch self {
        case .folder: return .home
        case .home: return .drive
        case .drive: return .mac
        case .mac: return nil
        }
    }

    /// Roots for NSMetadataQuery.searchScopes.
    public func spotlightScopes(home: String, drives: [GoogleDrive]) -> [String] {
        switch self {
        case .folder(let path): return [path]
        case .home: return [home]
        case .drive: return drives.isEmpty ? [home] : drives.map(\.root.path)
        case .mac: return [NSMetadataQueryLocalComputerScope]
        }
    }

    /// Whether a result at `path` is inside the scope, for IndexKit name matches.
    public func contains(_ path: String, home: String, drives: [GoogleDrive]) -> Bool {
        switch self {
        case .folder(let folder): return Self.isInside(path, folder)
        case .home: return Self.isInside(path, home)
        case .drive: return drives.contains { $0.contains(URL(fileURLWithPath: path)) }
        case .mac: return true
        }
    }

    static func isInside(_ path: String, _ folder: String) -> Bool {
        if folder == "/" { return path.hasPrefix("/") }
        return path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
