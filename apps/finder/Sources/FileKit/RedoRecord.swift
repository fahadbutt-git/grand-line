import Foundation

/// What one Undo did, so Redo can do the operation again from where Undo left
/// things. Like Undo, Redo never deletes: undone copies come back from the Trash.
struct RedoRecord: Sendable {
    enum Action: Sendable {
        /// Undone copies, duplicates and new folders: each from where it was made
        /// to where it went in the Trash.
        case restore([UndoRecord.Move])
        /// Undone moves: from where Undo put each item back to where it had gone.
        case move([UndoRecord.Move])
        /// Undone renames: from the old name to the new one.
        case rename(UndoRecord.Move)
        /// Undone Rename N Items: each from the old name to the new one.
        case renameMany([UndoRecord.Move])
        /// Undone trashing: the items, back in place, to go to the Trash again.
        case trash([URL])
    }

    let kind: FileOperationKind
    let action: Action
    /// Replaced items that Undo brought back, to go to the Trash again first.
    let replaced: [URL]
}
