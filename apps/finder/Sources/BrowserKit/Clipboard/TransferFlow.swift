import FileKit
import Foundation

/// A paste, a drop or Copy to Next Pane: taken names are asked about once,
/// before anything starts (`ConflictQuestions`), then the copy or move runs as
/// a task in the engine. Nexus's windows and the tests go through this one path.
public enum TransferFlow {
    /// What happened: what the task made, or that the questions were stopped.
    public enum Outcome: Equatable, Sendable {
        case done([URL])
        case stopped
    }

    /// Copies or moves `items` into `folder`. `ask` gets each conflict and how
    /// many come after it, and returns nil to stop (nothing then runs).
    /// Throws the task's error, or CancellationError when it was cancelled.
    public static func run(
        _ items: [URL], to folder: URL, moving: Bool, queue: FileTaskQueue,
        ask: (FileConflict, Int) async -> ConflictAnswer?
    ) async throws -> Outcome {
        guard !items.isEmpty else { return .done([]) }
        let conflicts = FileOperations.conflicts(items, in: folder)
        guard let resolution = await ConflictQuestions.resolve(conflicts, ask: ask) else { return .stopped }
        let kind: FileOperationKind = moving ? .move : .copy
        let made = try await queue.run(kind, title: TaskTitles.title(kind, items, to: folder)) { operations in
            if moving { return try await operations.move(items, to: folder, resolution: resolution) }
            return try await operations.copy(items, to: folder, resolution: resolution)
        }
        return .done(made)
    }
}
