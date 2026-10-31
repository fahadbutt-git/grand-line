import Foundation

/// Put Back (R21) for items Nexus moved to the Trash: where each one came from.
/// Undo covers the last operations; the ledger lasts across launches. Kept in
/// Application Support/Nexus/trash-ledger.json.
public struct TrashLedger: Codable, Equatable, Sendable {
    /// Path in the Trash to the original path.
    public private(set) var entries: [String: String] = [:]

    public init() {}

    public mutating func record(originals: [URL], trashed: [URL]) {
        for (original, trash) in zip(originals, trashed) {
            entries[trash.standardizedFileURL.path] = original.standardizedFileURL.path
        }
    }

    public func original(of trashed: URL) -> URL? {
        entries[trashed.standardizedFileURL.path].map { URL(fileURLWithPath: $0) }
    }

    public func canPutBack(_ items: [URL]) -> Bool {
        !items.isEmpty && items.allSatisfy { original(of: $0) != nil }
    }

    public mutating func forget(_ trashed: URL) {
        entries[trashed.standardizedFileURL.path] = nil
    }

    /// Drops entries whose item has left the Trash (emptied, or moved out by hand).
    public mutating func prune(exists: (String) -> Bool) {
        entries = entries.filter { exists($0.key) }
    }

    /// Where an item goes back to: its folder, and its old name, which the Trash
    /// may have changed ("Report 10.42.13.pdf").
    public func destination(of trashed: URL) -> (folder: URL, name: String)? {
        guard let original = original(of: trashed) else { return nil }
        return (original.deletingLastPathComponent(), original.lastPathComponent)
    }
}
