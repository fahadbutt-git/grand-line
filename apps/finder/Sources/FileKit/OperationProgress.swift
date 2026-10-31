import Foundation

/// What happens when an item of the same name is already at the destination.
public enum ConflictPolicy: Sendable, Equatable {
    /// Rename the new item "name 2", like Finder's Keep Both.
    case keepBoth
    /// Move the existing item to the Trash, so Undo can bring it back.
    case replace
    /// Leave the existing item and skip the new one.
    case skip
}

/// The answers to a task's conflicts: one policy for every name, with
/// exceptions by name (the conflict sheet's per-item answers before Apply to All).
public struct ConflictResolution: Sendable, Equatable {
    public var fallback: ConflictPolicy
    public var byName: [String: ConflictPolicy]

    public init(_ fallback: ConflictPolicy = .keepBoth, byName: [String: ConflictPolicy] = [:]) {
        self.fallback = fallback
        self.byName = byName
    }

    public func policy(for name: String) -> ConflictPolicy {
        byName[name] ?? fallback
    }
}

/// An item whose name is already taken at the destination.
public struct FileConflict: Sendable, Equatable {
    public let source: URL
    public let existing: URL

    public init(source: URL, existing: URL) {
        self.source = source
        self.existing = existing
    }

    public var name: String { source.lastPathComponent }
}

public enum FileOperationKind: String, Sendable, Equatable {
    case copy = "Copy"
    case move = "Move"
    case duplicate = "Duplicate"
    case rename = "Rename"
    case newFolder = "New Folder"
    case trash = "Move to Trash"
    /// Rename N Items: several renames done and undone as one.
    case renameItems = "Rename Items"
    case compress = "Compress"
    case extract = "Extract"
    case putBack = "Put Back"
}

public struct OperationProgress: Sendable, Equatable {
    public let kind: FileOperationKind
    public let completedFiles: Int
    public let totalFiles: Int
    public let completedBytes: Int64
    public let totalBytes: Int64
    /// The item being worked on, nil once finished.
    public let current: URL?

    public init(kind: FileOperationKind, completedFiles: Int, totalFiles: Int, completedBytes: Int64, totalBytes: Int64, current: URL?) {
        self.kind = kind
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.current = current
    }

    public var isFinished: Bool { current == nil && completedFiles >= totalFiles }

    public var fraction: Double {
        if totalBytes > 0 { return min(1, Double(completedBytes) / Double(totalBytes)) }
        return totalFiles > 0 ? min(1, Double(completedFiles) / Double(totalFiles)) : 1
    }
}

public enum FileOperationError: Error, Equatable {
    /// A folder cannot be copied or moved into itself or a folder inside it.
    case intoItself(URL)
    /// Replacing would trash an item that is being copied or moved.
    case replacesSource(URL)
    case invalidName(String)
    case nameTaken(String)
    case missing(URL)
    /// Two items of a batch rename would get the same name.
    case duplicateNames([String])
}
