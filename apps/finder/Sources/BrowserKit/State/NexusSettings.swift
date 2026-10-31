import Foundation

/// ~/.config/grand-line/nexus/settings.json. Every key is optional.
///
/// ```json
/// { "places": ["~/Downloads", "~/Developer"],
///   "projectFolders": ["~/Drive/Projects/Active"],
///   "projects": ["~/Developer/glaucoma-model"] }
/// ```
public struct NexusSettings: Codable, Equatable, Sendable {
    /// Sidebar Places; Finder's favourites when left out.
    public var places: [String]?
    /// Folders whose subfolders are the active projects.
    public var projectFolders: [String]?
    /// Single project folders.
    public var projects: [String]?

    public init(places: [String]? = nil, projectFolders: [String]? = nil, projects: [String]? = nil) {
        self.places = places
        self.projectFolders = projectFolders
        self.projects = projects
    }

    public static func load(_ url: URL) -> NexusSettings {
        JSONFile<NexusSettings>(url).read() ?? NexusSettings()
    }

    public static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2)), isDirectory: true) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The Active projects section: listed projects, then each project folder's
    /// subfolders by name. `children` lists a folder's subfolder names.
    public func projectURLs(home: URL, children: (URL) -> [String]) -> [URL] {
        var result = (projects ?? []).map { Self.expand($0, home: home) }
        for folder in (projectFolders ?? []).map({ Self.expand($0, home: home) }) {
            let names = children(folder)
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            result += names.map { folder.appendingPathComponent($0, isDirectory: true) }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public func placeURLs(home: URL) -> [URL]? {
        places.map { $0.map { Self.expand($0, home: home) } }
    }

    /// Add to Sidebar (Ctrl+Cmd+T): the folder joins the end of Places, which
    /// start from `current` (Finder's favourites when none are set). A folder
    /// already there is left where it is.
    public func addingPlace(_ folder: URL, current: [URL], home: URL) -> NexusSettings {
        let path = folder.standardizedFileURL.path
        guard !current.contains(where: { $0.standardizedFileURL.path == path }) else { return self }
        var copy = self
        copy.places = (current + [folder]).map { Self.abbreviate($0, home: home) }
        return copy
    }

    /// Remove from Sidebar for a place: Places become `current` without it.
    public func removingPlace(_ folder: URL, current: [URL], home: URL) -> NexusSettings {
        let path = folder.standardizedFileURL.path
        var copy = self
        copy.places = current.filter { $0.standardizedFileURL.path != path }.map { Self.abbreviate($0, home: home) }
        return copy
    }

    /// "~/Developer" for a folder in home, the full path otherwise.
    public static func abbreviate(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        if path == base { return "~" }
        if path.hasPrefix(base + "/") { return "~/" + path.dropFirst(base.count + 1) }
        return path
    }
}
