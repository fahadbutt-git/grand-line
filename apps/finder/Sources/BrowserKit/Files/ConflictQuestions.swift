import FileKit
import Foundation

/// The conflict sheet's answer for one item, and whether it holds for the
/// rest (Apply to All).
public struct ConflictAnswer: Equatable, Sendable {
    public let policy: ConflictPolicy
    public let applyToAll: Bool

    public init(_ policy: ConflictPolicy, applyToAll: Bool = false) {
        self.policy = policy
        self.applyToAll = applyToAll
    }
}

/// Asks about each taken name once, before a copy or move starts, so the task
/// itself never stops to ask (Finder asks per file, mid-copy). Replace moves
/// the old item to the Trash, so Undo brings it back.
public enum ConflictQuestions {
    /// "An item named “report.pdf” already exists in “Documents”."
    public static func message(for conflict: FileConflict) -> String {
        let folder = conflict.existing.deletingLastPathComponent().lastPathComponent
        return "An item named \u{201C}\(conflict.name)\u{201D} already exists in \u{201C}\(folder)\u{201D}."
    }

    /// The question's details: which item is newer, and what Replace does.
    public static func detail(for conflict: FileConflict, remaining: Int) -> String {
        var parts = [replaceNote]
        if let newer = newer(conflict) { parts.insert(newer, at: 0) }
        if remaining > 0 { parts.append(remaining == 1 ? "1 more item has the same problem." : "\(remaining) more items have the same problem.") }
        return parts.joined(separator: " ")
    }

    public static let replaceNote = "Replace moves the one already there to the Trash."

    static func newer(_ conflict: FileConflict) -> String? {
        let key: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let new = try? conflict.source.resourceValues(forKeys: key).contentModificationDate,
              let old = try? conflict.existing.resourceValues(forKeys: key).contentModificationDate,
              abs(new.timeIntervalSince(old)) >= 1 else { return nil }
        return new > old ? "The one you are adding is newer." : "The one already there is newer."
    }

    /// Asks `ask` about each conflict in turn until an answer applies to all.
    /// `ask` gets the conflict and how many come after it, and returns nil to
    /// stop the task. Returns nil when stopped.
    public static func resolve(
        _ conflicts: [FileConflict], ask: (FileConflict, Int) async -> ConflictAnswer?
    ) async -> ConflictResolution? {
        var resolution = ConflictResolution(.keepBoth)
        for (index, conflict) in conflicts.enumerated() {
            guard let answer = await ask(conflict, conflicts.count - index - 1) else { return nil }
            if answer.applyToAll {
                resolution.fallback = answer.policy
                return resolution
            }
            resolution.byName[conflict.name] = answer.policy
        }
        return resolution
    }
}
