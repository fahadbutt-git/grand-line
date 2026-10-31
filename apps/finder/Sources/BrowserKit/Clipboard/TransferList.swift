import FileKit
import Foundation

/// The tasks popover (R8): every task from FileKit's task engine with its
/// state and progress, the operation running in the background, and the last
/// ones that finished, from FileKit's progress stream.
public struct TransferList: Equatable, Sendable {
    public struct Done: Equatable, Sendable {
        public let kind: FileOperationKind
        public let files: Int
        public let bytes: Int64
        public let finished: Date
    }

    /// One task as the popover lists it.
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: FileTaskID
        public let kind: FileOperationKind?
        public let title: String
        public var state: FileTaskState
        /// The running operation's progress, while this task runs.
        public var progress: OperationProgress?
        public var changed: Date
        /// Asked to stop, and not stopped yet.
        public var cancelling = false

        /// "Waiting", "Copying 12 of 40", "Done", "Stopped", or why it failed.
        public var status: String {
            switch state {
            case .queued: return cancelling ? "Stopping" : "Waiting"
            case .running:
                if cancelling { return "Stopping" }
                guard let progress, progress.totalFiles > 0 else { return "Working" }
                return "\(TransferList.verb(progress.kind)) \(progress.completedFiles) of \(progress.totalFiles)"
            case .finished(let items): return items == 1 ? "Done, 1 item" : "Done, \(items) items"
            case .failed(let why): return why
            case .cancelled: return "Stopped"
            }
        }

        public var fraction: Double? {
            guard case .running = state else { return nil }
            return progress?.fraction ?? 0
        }
    }

    public private(set) var running: OperationProgress?
    public private(set) var done: [Done] = []
    /// Tasks, newest first: those still to finish, then those that ended.
    public private(set) var tasks: [Entry] = []
    public static let keep = 20

    public init() {}

    public var isBusy: Bool { running != nil || !active.isEmpty }

    /// Tasks waiting or running, oldest first.
    public var active: [Entry] { tasks.filter { !$0.state.isDone }.reversed() }

    /// Tasks that ended, newest first.
    public var ended: [Entry] { tasks.filter(\.state.isDone) }

    public mutating func apply(_ progress: OperationProgress, at date: Date = Date()) {
        if progress.isFinished {
            running = nil
            done.insert(Done(kind: progress.kind, files: progress.totalFiles, bytes: progress.totalBytes, finished: date), at: 0)
            if done.count > Self.keep { done.removeLast(done.count - Self.keep) }
        } else {
            running = progress
        }
        // Operations run one at a time, so the progress belongs to the running task.
        if let index = tasks.firstIndex(where: { $0.state == .running }) {
            tasks[index].progress = progress
            tasks[index].changed = date
        }
    }

    public mutating func apply(_ event: FileTaskEvent, at date: Date = Date()) {
        if let index = tasks.firstIndex(where: { $0.id == event.id }) {
            tasks[index].state = event.state
            tasks[index].changed = date
            if event.state.isDone {
                tasks[index].progress = nil
                tasks[index].cancelling = false
            }
        } else {
            tasks.insert(Entry(id: event.id, kind: event.kind, title: event.title, state: event.state, changed: date), at: 0)
        }
        let finished = tasks.indices.filter { tasks[$0].state.isDone }
        if finished.count > Self.keep {
            for index in finished.suffix(finished.count - Self.keep).reversed() { tasks.remove(at: index) }
        }
    }

    /// Cancel was pressed: the row says so until the engine reports the end.
    public mutating func markCancelling(_ id: FileTaskID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), !tasks[index].state.isDone else { return }
        tasks[index].cancelling = true
    }

    /// Forgets the tasks that ended (the popover's Clear).
    public mutating func clearEnded() {
        tasks.removeAll { $0.state.isDone }
        done = []
    }

    /// "Copying 12 of 40 files", "Moving to Trash 1 of 3".
    public var summary: String? {
        if let running {
            return "\(Self.verb(running.kind)) \(running.completedFiles) of \(running.totalFiles)"
        }
        let waiting = active.count
        guard waiting > 0 else { return nil }
        return waiting == 1 ? "1 task" : "\(waiting) tasks"
    }

    static func verb(_ kind: FileOperationKind) -> String {
        switch kind {
        case .copy: return "Copying"
        case .move: return "Moving"
        case .duplicate: return "Duplicating"
        case .rename: return "Renaming"
        case .renameItems: return "Renaming"
        case .newFolder: return "Making a folder"
        case .trash: return "Moving to Trash"
        case .compress: return "Compressing"
        case .extract: return "Extracting"
        case .putBack: return "Putting back"
        }
    }
}
