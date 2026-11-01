import FileKit
import Foundation

/// Put Back (R21) for items Nexus moved to the Trash: where each one came from.
/// Undo covers the last operations; the ledger lasts across launches. Kept in
/// Application Support/Nexus/trash-ledger.json.
///
/// Every item FileOperations sends to the Trash is recorded as it goes
/// (`FileOperations.trashChanges`), including those of a task stopped
/// halfway and those a Redo sends back; one that leaves the Trash is
/// forgotten. Each entry keeps the item's identity, so an item that later
/// takes the same name in the Trash is never sent to the first one's folder.
public struct TrashLedger: Codable, Equatable, Sendable {
    /// Path in the Trash to the original path.
    public private(set) var entries: [String: String] = [:]
    /// Path in the Trash to the identity of the item trashed there.
    public private(set) var stamps: [String: FileStamp] = [:]

    public init() {}

    enum CodingKeys: String, CodingKey {
        case entries, stamps
    }

    /// Ledgers written before identities were kept read as entries without them.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([String: String].self, forKey: .entries) ?? [:]
        stamps = try container.decodeIfPresent([String: FileStamp].self, forKey: .stamps) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(stamps, forKey: .stamps)
    }

    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    public mutating func record(originals: [URL], trashed: [URL]) {
        for (original, trash) in zip(originals, trashed) {
            record(original: original, trashed: trash, stamp: FileStamp.of(trash))
        }
    }

    public mutating func record(original: URL, trashed: URL, stamp: FileStamp?) {
        let key = Self.key(trashed)
        entries[key] = Self.key(original)
        stamps[key] = stamp
    }

    /// Takes in one change reported by FileOperations.
    public mutating func apply(_ change: TrashChange) {
        switch change {
        case .trashed(let original, let trashed, let stamp):
            record(original: original, trashed: trashed, stamp: stamp)
        case .left(let trashed):
            forget(trashed)
        }
    }

    /// Where the item at `trashed` came from, when it is still the item that
    /// was trashed there.
    public func original(of trashed: URL) -> URL? {
        let key = Self.key(trashed)
        guard let path = entries[key] else { return nil }
        if let stamp = stamps[key], FileStamp.of(trashed) != stamp { return nil }
        return URL(fileURLWithPath: path)
    }

    public func canPutBack(_ items: [URL]) -> Bool {
        !items.isEmpty && items.allSatisfy { original(of: $0) != nil }
    }

    public mutating func forget(_ trashed: URL) {
        let key = Self.key(trashed)
        entries[key] = nil
        stamps[key] = nil
    }

    /// Drops entries whose item has left the Trash (emptied, or moved out by hand).
    public mutating func prune(exists: (String) -> Bool) {
        entries = entries.filter { exists($0.key) }
        stamps = stamps.filter { entries[$0.key] != nil }
    }

    /// Where an item goes back to: its folder, and its old name, which the Trash
    /// may have changed ("Report 10.42.13.pdf").
    public func destination(of trashed: URL) -> (folder: URL, name: String)? {
        guard let original = original(of: trashed) else { return nil }
        return (original.deletingLastPathComponent(), original.lastPathComponent)
    }
}
