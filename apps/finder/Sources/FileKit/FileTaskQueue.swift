import Foundation

/// A task's number, in the order tasks were asked for.
public struct FileTaskID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public static func < (a: FileTaskID, b: FileTaskID) -> Bool { a.value < b.value }

    public var description: String { "task \(value)" }
}

public enum FileTaskState: Sendable, Equatable {
    /// Waiting for the tasks before it.
    case queued
    case running
    /// Done; `items` is how many items it made or moved.
    case finished(items: Int)
    case failed(String)
    case cancelled

    public var isDone: Bool {
        switch self {
        case .queued, .running: return false
        case .finished, .failed, .cancelled: return true
        }
    }
}

/// A change in one task, in the order they happen.
public struct FileTaskEvent: Sendable, Equatable {
    public let id: FileTaskID
    /// nil for Undo and Redo, which reverse other tasks.
    public let kind: FileOperationKind?
    /// "Copy 3 items to Documents".
    public let title: String
    public let state: FileTaskState

    public init(id: FileTaskID, kind: FileOperationKind?, title: String, state: FileTaskState) {
        self.id = id
        self.kind = kind
        self.title = title
        self.state = state
    }
}

/// The task engine: every copy, move, Trash, duplicate, rename, compress and
/// extract runs as a task, one after another in the order asked (yazi, Files'
/// Status Center). Each can be cancelled while it waits or while it runs;
/// FileOperations then stops between files and keeps what it did undoable.
/// `events` reports each task's state; the operations' own `progress` stream
/// belongs to the task that is running.
public actor FileTaskQueue {
    public typealias Body = @Sendable (FileOperations) async throws -> [URL]

    public nonisolated let operations: FileOperations
    public nonisolated let events: AsyncStream<FileTaskEvent>
    private nonisolated let continuation: AsyncStream<FileTaskEvent>.Continuation
    private var tasks: [FileTaskID: Task<[URL], Error>] = [:]
    private var states: [FileTaskID: FileTaskState] = [:]
    private var last: Task<[URL], Error>?
    private var nextID = 1

    public init(operations: FileOperations) {
        self.operations = operations
        let (stream, continuation) = AsyncStream.makeStream(of: FileTaskEvent.self, bufferingPolicy: .bufferingNewest(512))
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    /// Adds a task after the others and returns at once.
    @discardableResult
    public func enqueue(_ kind: FileOperationKind?, title: String, body: @escaping Body) -> FileTaskID {
        add(kind, title: title, body: body).id
    }

    /// Adds a task after the others and waits for it. Throws CancellationError
    /// when it was cancelled, or the operation's own error.
    @discardableResult
    public func run(_ kind: FileOperationKind?, title: String, body: @escaping Body) async throws -> [URL] {
        let task = add(kind, title: title, body: body).task
        return try await task.value
    }

    /// Stops a task: one still waiting never starts, a running one stops
    /// between files.
    public func cancel(_ id: FileTaskID) {
        tasks[id]?.cancel()
    }

    public func cancelAll() {
        for task in tasks.values { task.cancel() }
    }

    /// The state of a task, nil once it is long forgotten.
    public func state(of id: FileTaskID) -> FileTaskState? {
        states[id]
    }

    /// Tasks not yet done, oldest first.
    public var pending: [FileTaskID] {
        states.filter { !$0.value.isDone }.keys.sorted()
    }

    /// Waits until every task asked for so far is done.
    public func waitUntilIdle() async {
        _ = await last?.result
    }

    private func add(_ kind: FileOperationKind?, title: String, body: @escaping Body) -> (id: FileTaskID, task: Task<[URL], Error>) {
        let id = FileTaskID(nextID)
        nextID += 1
        let previous = last
        let operations = self.operations
        set(id, kind, title, .queued)
        let task = Task<[URL], Error> {
            // One at a time: wait for the task before this one, however it ended.
            _ = await previous?.result
            if Task.isCancelled {
                await self.set(id, kind, title, .cancelled)
                throw CancellationError()
            }
            await self.set(id, kind, title, .running)
            do {
                let made = try await body(operations)
                await self.set(id, kind, title, .finished(items: made.count))
                return made
            } catch is CancellationError {
                await self.set(id, kind, title, .cancelled)
                throw CancellationError()
            } catch {
                await self.set(id, kind, title, .failed(Self.describe(error)))
                throw error
            }
        }
        tasks[id] = task
        last = task
        return (id, task)
    }

    private func set(_ id: FileTaskID, _ kind: FileOperationKind?, _ title: String, _ state: FileTaskState) {
        states[id] = state
        if state.isDone {
            tasks[id] = nil
            // Keep the last hundred answers for `state(of:)`.
            if states.count > 100, let oldest = states.filter({ $0.value.isDone }).keys.min() { states[oldest] = nil }
        }
        continuation.yield(FileTaskEvent(id: id, kind: kind, title: title, state: state))
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? FileOperationError {
            switch error {
            case .intoItself(let url): return "\(url.lastPathComponent) cannot go inside itself."
            case .replacesSource(let url): return "\(url.lastPathComponent) is one of the items being moved."
            case .invalidName(let name): return "\u{201C}\(name)\u{201D} cannot be used as a name."
            case .nameTaken(let name): return "\u{201C}\(name)\u{201D} is already taken."
            case .missing(let url): return "\(url.lastPathComponent) is no longer there."
            case .duplicateNames(let names): return "Two items would be named \u{201C}\(names.first ?? "")\u{201D}."
            }
        }
        return error.localizedDescription
    }
}
