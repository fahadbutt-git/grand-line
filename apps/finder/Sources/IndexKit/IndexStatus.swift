import Foundation

/// What a settings window shows about the name index.
public struct IndexStatus: Sendable, Equatable, Codable {
    /// Where the answers come from.
    public enum Source: String, Sendable, Codable {
        /// The Grand Line Index background service.
        case service
        /// The app's own copy, read from the service's snapshot, while the
        /// service cannot be reached.
        case inApp
    }

    /// Files and folders in the index.
    public var files: Int
    /// When the index last matched the disk, if known.
    public var lastSync: Date?
    /// True while a walk of the folders is under way.
    public var building: Bool
    /// Folders macOS would not let the index read.
    public var unreadable: [String]
    /// False while the index holds only part of its folders.
    public var complete: Bool
    /// The folders the index covers.
    public var roots: [String]
    public var source: Source
    /// Why the service is not answering, when that is known (it is signed
    /// differently from the app), for Settings to show.
    public var problem: String?

    public init(
        files: Int, lastSync: Date?, building: Bool, unreadable: [String],
        complete: Bool = true, roots: [String] = [], source: Source = .inApp, problem: String? = nil
    ) {
        self.files = files
        self.lastSync = lastSync
        self.building = building
        self.unreadable = unreadable
        self.complete = complete
        self.roots = roots
        self.source = source
        self.problem = problem
    }

    public static let empty = IndexStatus(files: 0, lastSync: nil, building: false, unreadable: [], complete: false)

    /// As sent between the service and its clients.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(self)) ?? Data()
    }

    public init?(encoded data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let status = try? decoder.decode(IndexStatus.self, from: data) else { return nil }
        self = status
    }
}

/// What the Settings windows of Nexus and Sight call for the index section:
/// its state, and a Rebuild button.
public protocol IndexStatusProviding: Sendable {
    func status() async -> IndexStatus
    /// Walks every folder again. Returns once the walk has started; `status()`
    /// reports `building` until it ends.
    func rebuild() async
}

/// What one caller's last search matched, so a query typed on from it only
/// searches those entries. Each caller keeps its own: one per window, one per
/// client of the index service.
public struct SearchNarrowing: Sendable {
    let query: SearchQuery
    let generation: Int
    let scope: [String]
    let matched: [Int32]
}
