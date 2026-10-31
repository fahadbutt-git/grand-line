import Foundation

/// Where the shared name index and the apps' older copies live.
public struct IndexLocations: Sendable, Equatable {
    /// The home folder, as the process sees it.
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// ~/Library/Application Support/Grand Line Index.
    public var folder: URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Grand Line Index", isDirectory: true)
    }

    /// The service's snapshot. Clients read it when the service is out of reach.
    public var snapshot: URL { folder.appendingPathComponent("names.index") }
    /// When the last weekly sweep ran, and such.
    public var state: URL { folder.appendingPathComponent("service-state.json") }

    /// The snapshot Sight kept before the service (GrandLinePaths.index).
    public var sightSnapshot: URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Sight/names.index")
    }

    /// The snapshot Nexus kept before the service (AppPaths.nameIndex).
    public var nexusSnapshot: URL {
        URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Nexus/name-index.snapshot")
    }

    /// The one root the shared index covers: the home folder, as a real path.
    public var roots: [String] { [FolderWatcher.realPath(home)] }
}

/// Which saved index to start from: the service's own, else the best of what
/// Sight and Nexus saved before there was a service, so nothing is walked again.
public enum SnapshotAdoption {
    public enum Origin: String, Sendable, Equatable {
        case own, sight, nexus
    }

    public struct Candidate: Sendable, Equatable {
        public let url: URL
        public let origin: Origin
        public let modified: Date
        public let complete: Bool
        public let roots: [String]

        public init(url: URL, origin: Origin, modified: Date, complete: Bool, roots: [String]) {
            self.url = url
            self.origin = origin
            self.modified = modified
            self.complete = complete
            self.roots = roots
        }
    }

    /// The snapshots to try, best first. Only snapshots of the same roots count.
    /// The service's own comes first whatever its age: the apps stop saving
    /// theirs once the service exists. Of the apps' snapshots, a finished one
    /// comes before an unfinished one, then the newer before the older.
    public static func ranked(_ candidates: [Candidate], roots: [String]) -> [Candidate] {
        let usable = candidates.filter { $0.roots == roots }
        let own = usable.filter { $0.origin == .own }
        let others = usable.filter { $0.origin != .own }.sorted { a, b in
            if a.complete != b.complete { return a.complete }
            if a.modified != b.modified { return a.modified > b.modified }
            return a.origin.rawValue > b.origin.rawValue
        }
        return own + others
    }

    public static func choose(_ candidates: [Candidate], roots: [String]) -> Candidate? {
        ranked(candidates, roots: roots).first
    }

    /// The snapshots on disk, read only as far as their headers.
    public static func candidates(_ locations: IndexLocations) -> [Candidate] {
        let files: [(URL, Origin)] = [
            (locations.snapshot, .own),
            (locations.sightSnapshot, .sight),
            (locations.nexusSnapshot, .nexus),
        ]
        var found: [Candidate] = []
        for (url, origin) in files {
            guard let header = header(of: url) else { continue }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            found.append(Candidate(
                url: url, origin: origin, modified: modified ?? .distantPast,
                complete: header.complete, roots: header.roots
            ))
        }
        return found
    }

    /// Loads the best snapshot that decodes, or nil when there is none.
    public static func load(
        _ locations: IndexLocations, exclusions: IndexExclusions, order: ScanOrder
    ) -> (index: FileIndex, origin: Origin)? {
        for candidate in ranked(candidates(locations), roots: locations.roots) {
            if let index = try? FileIndex.load(from: candidate.url, exclusions: exclusions, order: order) {
                return (index, candidate.origin)
            }
        }
        return nil
    }

    static func header(of url: URL) -> IndexSnapshot.Header? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536) else { return nil }
        return try? IndexSnapshot.header(of: data)
    }
}
