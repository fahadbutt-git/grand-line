import Foundation

/// A saved window (R12, R27): its panes, where each one is, and how it looks.
public struct Workspace: Codable, Equatable, Sendable {
    public struct Pane: Codable, Equatable, Sendable {
        public var location: BrowserLocation
        public var mode: ViewMode

        public init(location: BrowserLocation, mode: ViewMode) {
            self.location = location
            self.mode = mode
        }
    }

    public var name: String
    public var layout: PaneLayout
    public var panes: [Pane]
    /// A pinned window floats above others and stays on its folder.
    public var pinned: Bool
    public var sidebarWidth: Double

    public init(name: String, layout: PaneLayout, panes: [Pane], pinned: Bool = false, sidebarWidth: Double = SidebarMetrics.defaultWidth) {
        self.name = name
        self.layout = layout
        self.panes = panes
        self.pinned = pinned
        self.sidebarWidth = sidebarWidth
    }

    /// Searches and Recents are not saved; their panes come back at home.
    public func restorable(home: URL) -> Workspace {
        var copy = self
        copy.panes = panes.prefix(layout.count).map { pane in
            switch pane.location {
            case .folder, .archive: return pane
            case .search, .recents: return Pane(location: .folder(home), mode: pane.mode)
            }
        }
        while copy.panes.count < layout.count {
            copy.panes.append(Pane(location: .folder(home), mode: .list))
        }
        return copy
    }
}

/// Workspaces as one JSON file each in Application Support/Nexus/Workspaces.
public struct WorkspaceStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func names() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files
            .filter { $0.hasSuffix(".json") }
            .compactMap { load(file: folder.appendingPathComponent($0))?.name }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func load(_ name: String) -> Workspace? {
        load(file: file(for: name))
    }

    public func save(_ workspace: Workspace) throws {
        try JSONFile<Workspace>(file(for: workspace.name)).write(workspace)
    }

    /// The file goes to the Trash, like everything else.
    public func remove(_ name: String) throws {
        let url = file(for: name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    func load(file: URL) -> Workspace? {
        JSONFile<Workspace>(file).read()
    }

    func file(for name: String) -> URL {
        let safe = name.map { "/:\\".contains($0) ? "-" : $0 }
        return folder.appendingPathComponent(String(safe) + ".json")
    }
}
