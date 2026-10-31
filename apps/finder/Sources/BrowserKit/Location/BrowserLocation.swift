import Foundation

/// What a pane shows.
public enum BrowserLocation: Hashable, Codable, Sendable {
    case folder(URL)
    /// A folder inside an archive (R26); "" is the archive's top level.
    case archive(URL, entry: String)
    case search(query: String, scope: SearchScope)
    case recents

    public var title: String {
        switch self {
        case .folder(let url): return url.path == "/" ? "/" : url.lastPathComponent
        case .archive(let url, let entry): return entry.isEmpty ? url.lastPathComponent : (entry as NSString).lastPathComponent
        case .search(let query, _): return "Search: " + query
        case .recents: return "Recents"
        }
    }

    /// The real folder, where new items, pastes and drops go. nil inside an
    /// archive, a search or Recents.
    public var folderURL: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }

    /// The folder on disk this location belongs to: an archive's own folder for
    /// an archive, nil for searches and Recents.
    public var diskFolder: URL? {
        switch self {
        case .folder(let url): return url
        case .archive(let url, _): return url.deletingLastPathComponent()
        case .search, .recents: return nil
        }
    }

    public var isArchive: Bool {
        if case .archive = self { return true }
        return false
    }

    /// Up (Cmd+Up, R4): the enclosing folder, and the item to select there.
    public var parent: (location: BrowserLocation, select: URL?)? {
        switch self {
        case .folder(let url):
            let standard = url.standardizedFileURL
            guard standard.path != "/" else { return nil }
            return (.folder(standard.deletingLastPathComponent()), standard)
        case .archive(let url, let entry):
            if entry.isEmpty { return (.folder(url.deletingLastPathComponent()), url) }
            let up = (entry as NSString).deletingLastPathComponent
            return (.archive(url, entry: up), url.appendingPathComponent(entry))
        case .search, .recents:
            return nil
        }
    }
}
