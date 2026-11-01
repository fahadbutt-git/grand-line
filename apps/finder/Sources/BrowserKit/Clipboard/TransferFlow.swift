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
        // Looked up off the main thread: each item's name is checked on disk.
        let conflicts = await Task.detached(priority: .userInitiated) { FileOperations.conflicts(items, in: folder) }.value
        let kind: FileOperationKind = moving ? .move : .copy
        let title = TaskTitles.title(kind, items, to: folder)
        let taken: String = conflicts.isEmpty ? "" : " (" + NexusLog.names(conflicts.map(\.existing)) + "), asking"
        NexusLog.note("\(title): \(conflicts.count) taken name(s)" + taken)
        guard let resolution = await ConflictQuestions.resolve(conflicts, ask: ask) else {
            NexusLog.note("\(title): stopped at the conflict question, nothing ran")
            return .stopped
        }
        do {
            let made = try await queue.run(kind, title: title) { operations in
                if moving { return try await operations.move(items, to: folder, resolution: resolution) }
                return try await operations.copy(items, to: folder, resolution: resolution)
            }
            NexusLog.note("\(title): made \(made.isEmpty ? "nothing" : NexusLog.names(made))")
            return .done(made)
        } catch is CancellationError {
            NexusLog.note("\(title): cancelled")
            throw CancellationError()
        } catch {
            NexusLog.note("\(title): failed: \(FileTaskQueue.describe(error))")
            throw error
        }
    }
}
