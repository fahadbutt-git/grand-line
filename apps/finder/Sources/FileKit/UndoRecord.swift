import Foundation

/// What one operation did, so Undo can reverse it. Nothing is ever deleted:
/// undoing a copy moves the copies to the Trash, and anything replaced comes back
/// from the Trash.
struct UndoRecord: Sendable {
    struct Move: Sendable, Equatable {
        let from: URL
        let to: URL
    }

    enum Action: Sendable {
        /// Items made by copy, duplicate, new folder, compress or extract.
        case created([URL])
        case moved([Move])
        case renamed(Move)
        /// Rename N Items: every rename, from the old name to the new one.
        case renamedMany([Move])
        /// Items moved to the Trash: from the original place to the Trash.
        case trashed([Move])
    }

    let kind: FileOperationKind
    let action: Action
    /// Items moved to the Trash to make room under the replace policy.
    let replaced: [Move]
    var date: Date = Date()

    /// The items as they are after the operation, for the history list.
    var items: [URL] {
        switch action {
        case .created(let urls): return urls
        case .moved(let moves), .renamedMany(let moves): return moves.map(\.to)
        case .renamed(let move): return [move.to]
        case .trashed(let moves): return moves.map(\.from)
        }
    }

    var summary: OperationRecord {
        let urls = items
        return OperationRecord(kind: kind, count: urls.count, names: urls.prefix(3).map(\.lastPathComponent), date: date)
    }
}

/// One entry in the undo history, newest first in `FileOperations.history`.
public struct OperationRecord: Sendable, Equatable {
    public let kind: FileOperationKind
    /// How many items it touched.
    public let count: Int
    /// The first few items' names.
    public let names: [String]
    public let date: Date

    public init(kind: FileOperationKind, count: Int, names: [String], date: Date) {
        self.kind = kind
        self.count = count
        self.names = names
        self.date = date
    }
}
