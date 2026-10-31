import FileKit
import Foundation

/// The transfers popover (R8): the operation running in the background and the
/// last ones that finished, from FileKit's progress stream.
public struct TransferList: Equatable, Sendable {
    public struct Done: Equatable, Sendable {
        public let kind: FileOperationKind
        public let files: Int
        public let bytes: Int64
        public let finished: Date
    }

    public private(set) var running: OperationProgress?
    public private(set) var done: [Done] = []
    public static let keep = 20

    public init() {}

    public var isBusy: Bool { running != nil }

    public mutating func apply(_ progress: OperationProgress, at date: Date = Date()) {
        if progress.isFinished {
            running = nil
            done.insert(Done(kind: progress.kind, files: progress.totalFiles, bytes: progress.totalBytes, finished: date), at: 0)
            if done.count > Self.keep { done.removeLast(done.count - Self.keep) }
        } else {
            running = progress
        }
    }

    /// "Copying 12 of 40 files", "Moving to Trash 1 of 3".
    public var summary: String? {
        guard let running else { return nil }
        let verb: String
        switch running.kind {
        case .copy: verb = "Copying"
        case .move: verb = "Moving"
        case .duplicate: verb = "Duplicating"
        case .rename: verb = "Renaming"
        case .newFolder: verb = "Making a folder"
        case .trash: verb = "Moving to Trash"
        }
        return "\(verb) \(running.completedFiles) of \(running.totalFiles)"
    }
}
