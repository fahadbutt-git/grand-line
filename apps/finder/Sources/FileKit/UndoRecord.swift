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
        /// Items made by copy, duplicate or new folder.
        case created([URL])
        case moved([Move])
        case renamed(Move)
        /// Items moved to the Trash: from the original place to the Trash.
        case trashed([Move])
    }

    let kind: FileOperationKind
    let action: Action
    /// Items moved to the Trash to make room under the replace policy.
    let replaced: [Move]
}
