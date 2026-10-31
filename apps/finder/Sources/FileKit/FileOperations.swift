import Foundation

/// Copy, move, duplicate, rename, new folder and move to Trash, each undoable
/// and redoable.
/// Nothing is ever deleted outright: replaced items and undone copies go to the Trash.
/// Operations run one at a time, in the order asked, the way Nimble Commander
/// queues them.
public actor FileOperations {
    /// Moves an item to the Trash and returns where it went.
    public typealias Trash = @Sendable (URL) throws -> URL

    public static let systemTrash: Trash = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    /// Progress of the running operation. One reader at a time.
    public nonisolated let progress: AsyncStream<OperationProgress>
    private let progressContinuation: AsyncStream<OperationProgress>.Continuation
    private let trash: Trash
    private var undoStack: [UndoRecord] = []
    private var redoStack: [RedoRecord] = []
    private var cutItems: [URL] = []
    static let undoLimit = 50

    struct Step {
        let source: URL
        let destination: URL
        let replaces: Bool
    }

    public init(trash: @escaping Trash = FileOperations.systemTrash) {
        let (stream, continuation) = AsyncStream.makeStream(
            of: OperationProgress.self, bufferingPolicy: .bufferingNewest(256)
        )
        self.progress = stream
        self.progressContinuation = continuation
        self.trash = trash
    }

    deinit {
        progressContinuation.finish()
    }

    // MARK: Operations

    /// Copies items into a folder. Copying into the items' own folder keeps both.
    @discardableResult
    public func copy(_ items: [URL], to folder: URL, conflict: ConflictPolicy = .keepBoth) throws -> [URL] {
        try copySteps(plan(items, into: folder, conflict: conflict, moving: false), kind: .copy)
    }

    /// Moves items into a folder. Items already there are left alone.
    @discardableResult
    public func move(_ items: [URL], to folder: URL, conflict: ConflictPolicy = .keepBoth) throws -> [URL] {
        let steps = try plan(items, into: folder, conflict: conflict, moving: true)
        var moves: [UndoRecord.Move] = []
        var replaced: [UndoRecord.Move] = []
        report(.move, done: 0, of: steps.count, current: steps.first?.source)
        do {
            for (i, step) in steps.enumerated() {
                if step.replaces { replaced.append(.init(from: step.destination, to: try trash(step.destination))) }
                try FileManager.default.moveItem(at: step.source, to: step.destination)
                moves.append(.init(from: step.source, to: step.destination))
                report(.move, done: i + 1, of: steps.count, current: i + 1 < steps.count ? steps[i + 1].source : nil)
            }
        } catch {
            push(UndoRecord(kind: .move, action: .moved(moves), replaced: replaced))
            throw error
        }
        push(UndoRecord(kind: .move, action: .moved(moves), replaced: replaced))
        return moves.map(\.to)
    }

    /// Remembers items for a later `pasteCut(into:)`, which moves them.
    public func cut(_ items: [URL]) {
        cutItems = items
    }

    public var cutPending: [URL] { cutItems }

    public func cancelCut() {
        cutItems = []
    }

    @discardableResult
    public func pasteCut(into folder: URL, conflict: ConflictPolicy = .keepBoth) throws -> [URL] {
        let items = cutItems
        guard !items.isEmpty else { return [] }
        cutItems = []
        return try move(items, to: folder, conflict: conflict)
    }

    /// "Report copy.pdf" next to "Report.pdf".
    @discardableResult
    public func duplicate(_ items: [URL]) throws -> [URL] {
        var taken = Set<String>()
        var steps: [Step] = []
        for item in items {
            guard FileTree.exists(item) else { throw FileOperationError.missing(item) }
            let folder = item.deletingLastPathComponent()
            let name = FileNaming.duplicate(item.lastPathComponent, in: folder, avoiding: taken)
            taken.insert(name)
            steps.append(Step(source: item, destination: folder.appendingPathComponent(name), replaces: false))
        }
        return try copySteps(steps, kind: .duplicate)
    }

    @discardableResult
    public func rename(_ item: URL, to name: String) throws -> URL {
        guard FileNaming.isValid(name) else { throw FileOperationError.invalidName(name) }
        guard FileTree.exists(item) else { throw FileOperationError.missing(item) }
        if name == item.lastPathComponent { return item }
        let destination = item.deletingLastPathComponent().appendingPathComponent(name)
        if FileTree.exists(destination), !Self.isSameItem(item, destination) {
            throw FileOperationError.nameTaken(name)
        }
        try Self.place(item, at: destination)
        push(UndoRecord(kind: .rename, action: .renamed(.init(from: item, to: destination)), replaced: []))
        return destination
    }

    /// Makes "untitled folder", or "untitled folder 2" when that exists.
    @discardableResult
    public func newFolder(in folder: URL, named name: String = "untitled folder") throws -> URL {
        guard FileNaming.isValid(name) else { throw FileOperationError.invalidName(name) }
        let url = folder.appendingPathComponent(FileNaming.available(name, in: folder))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        push(UndoRecord(kind: .newFolder, action: .created([url]), replaced: []))
        return url
    }

    /// Returns where each item went in the Trash.
    @discardableResult
    public func moveToTrash(_ items: [URL]) throws -> [URL] {
        var moves: [UndoRecord.Move] = []
        report(.trash, done: 0, of: items.count, current: items.first)
        do {
            for (i, item) in items.enumerated() {
                moves.append(.init(from: item, to: try trash(item)))
                report(.trash, done: i + 1, of: items.count, current: i + 1 < items.count ? items[i + 1] : nil)
            }
        } catch {
            push(UndoRecord(kind: .trash, action: .trashed(moves), replaced: []))
            throw error
        }
        push(UndoRecord(kind: .trash, action: .trashed(moves), replaced: []))
        return moves.map(\.to)
    }

    // MARK: Undo and Redo

    /// The operation Undo would reverse, for the Edit menu ("Undo Copy").
    public var undoKind: FileOperationKind? { undoStack.last?.kind }

    /// The operation Redo would do again, for the Edit menu ("Redo Copy").
    public var redoKind: FileOperationKind? { redoStack.last?.kind }

    /// Reverses the last operation. Returns what was undone, nil when there was nothing.
    @discardableResult
    public func undo() throws -> FileOperationKind? {
        guard let record = undoStack.popLast() else { return nil }
        let action: RedoRecord.Action
        switch record.action {
        case .created(let items):
            var trashed: [UndoRecord.Move] = []
            for item in items.reversed() where FileTree.exists(item) {
                trashed.append(.init(from: item, to: try trash(item)))
            }
            action = .restore(trashed)
        case .moved(let moves):
            var back: [UndoRecord.Move] = []
            for move in moves.reversed() {
                let spot = Self.freeSpot(for: move.from)
                try Self.place(move.to, at: spot)
                back.append(.init(from: spot, to: move.to))
            }
            action = .move(back)
        case .trashed(let moves):
            var restored: [URL] = []
            for move in moves.reversed() {
                let spot = Self.freeSpot(for: move.from)
                try Self.place(move.to, at: spot)
                restored.append(spot)
            }
            action = .trash(restored)
        case .renamed(let move):
            try Self.place(move.to, at: move.from)
            action = .rename(move)
        }
        var replaced: [URL] = []
        for item in record.replaced.reversed() {
            let spot = Self.freeSpot(for: item.from)
            try Self.place(item.to, at: spot)
            replaced.append(spot)
        }
        redoStack.append(RedoRecord(kind: record.kind, action: action, replaced: replaced))
        if redoStack.count > Self.undoLimit { redoStack.removeFirst() }
        return record.kind
    }

    /// Does the last undone operation again, and makes it undoable once more.
    /// Returns what was redone, nil when there was nothing.
    @discardableResult
    public func redo() throws -> FileOperationKind? {
        guard let record = redoStack.popLast() else { return nil }
        var replaced: [UndoRecord.Move] = []
        for item in record.replaced where FileTree.exists(item) {
            replaced.append(.init(from: item, to: try trash(item)))
        }
        let action: UndoRecord.Action
        switch record.action {
        case .restore(let moves):
            var created: [URL] = []
            for move in moves.reversed() {
                let spot = Self.freeSpot(for: move.from)
                try Self.place(move.to, at: spot)
                created.append(spot)
            }
            action = .created(created)
        case .move(let moves):
            var done: [UndoRecord.Move] = []
            for move in moves.reversed() {
                let spot = Self.freeSpot(for: move.to)
                try Self.place(move.from, at: spot)
                done.append(.init(from: move.from, to: spot))
            }
            action = .moved(done)
        case .rename(let move):
            if FileTree.exists(move.to), !Self.isSameItem(move.from, move.to) {
                throw FileOperationError.nameTaken(move.to.lastPathComponent)
            }
            try Self.place(move.from, at: move.to)
            action = .renamed(move)
        case .trash(let items):
            var trashed: [UndoRecord.Move] = []
            for item in items {
                trashed.append(.init(from: item, to: try trash(item)))
            }
            action = .trashed(trashed)
        }
        push(UndoRecord(kind: record.kind, action: action, replaced: replaced), clearingRedo: false)
        return record.kind
    }

    // MARK: Helpers

    func plan(_ items: [URL], into folder: URL, conflict: ConflictPolicy, moving: Bool) throws -> [Step] {
        var steps: [Step] = []
        var taken = Set<String>()
        for item in items {
            guard FileTree.exists(item) else { throw FileOperationError.missing(item) }
            if FileTree.isInside(folder, item) { throw FileOperationError.intoItself(item) }
            let name = item.lastPathComponent
            let sameFolder = item.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
            if moving && sameFolder { continue }
            var destination = folder.appendingPathComponent(name)
            var replaces = false
            if taken.contains(name) || sameFolder {
                destination = folder.appendingPathComponent(FileNaming.keepBoth(name, in: folder, avoiding: taken))
            } else if FileTree.exists(destination) {
                switch conflict {
                case .skip:
                    continue
                case .keepBoth:
                    destination = folder.appendingPathComponent(FileNaming.keepBoth(name, in: folder, avoiding: taken))
                case .replace:
                    if items.contains(where: { FileTree.isInside($0, destination) }) {
                        throw FileOperationError.replacesSource(destination)
                    }
                    replaces = true
                }
            }
            taken.insert(destination.lastPathComponent)
            steps.append(Step(source: item, destination: destination, replaces: replaces))
        }
        return steps
    }

    private func copySteps(_ steps: [Step], kind: FileOperationKind) throws -> [URL] {
        let sizes = steps.map { FileTree.measure($0.source) }
        let totalFiles = sizes.reduce(0) { $0 + $1.files }
        let totalBytes = sizes.reduce(Int64(0)) { $0 + $1.bytes }
        var files = 0
        var bytes: Int64 = 0
        var created: [URL] = []
        var replaced: [UndoRecord.Move] = []
        report(kind, files: 0, of: totalFiles, bytes: 0, of: totalBytes, current: steps.first?.source)
        do {
            for step in steps {
                if step.replaces { replaced.append(.init(from: step.destination, to: try trash(step.destination))) }
                try FileTree.copy(step.source, to: step.destination) { file, size in
                    files += 1
                    bytes += size
                    report(kind, files: files, of: totalFiles, bytes: bytes, of: totalBytes, current: file)
                }
                created.append(step.destination)
            }
        } catch {
            push(UndoRecord(kind: kind, action: .created(created), replaced: replaced))
            throw error
        }
        report(kind, files: totalFiles, of: totalFiles, bytes: totalBytes, of: totalBytes, current: nil)
        push(UndoRecord(kind: kind, action: .created(created), replaced: replaced))
        return created
    }

    /// A new operation ends what Redo could do again, as in every Mac app.
    private func push(_ record: UndoRecord, clearingRedo: Bool = true) {
        if clearingRedo { redoStack.removeAll() }
        undoStack.append(record)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
    }

    private func report(_ kind: FileOperationKind, done: Int, of total: Int, current: URL?) {
        report(kind, files: done, of: total, bytes: 0, of: 0, current: current)
    }

    private func report(
        _ kind: FileOperationKind, files: Int, of totalFiles: Int, bytes: Int64, of totalBytes: Int64, current: URL?
    ) {
        progressContinuation.yield(OperationProgress(
            kind: kind, completedFiles: files, totalFiles: totalFiles,
            completedBytes: bytes, totalBytes: totalBytes, current: current
        ))
    }

    /// Moves an item, including a change of case only ("a.txt" to "A.txt").
    static func place(_ source: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if source.lastPathComponent.lowercased() == destination.lastPathComponent.lowercased(),
           source.deletingLastPathComponent().standardizedFileURL == destination.deletingLastPathComponent().standardizedFileURL {
            let temporary = source.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
            try fileManager.moveItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    /// The original place, or a keep-both name beside it when something new is there.
    static func freeSpot(for url: URL) -> URL {
        guard FileTree.exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        return folder.appendingPathComponent(FileNaming.keepBoth(url.lastPathComponent, in: folder))
    }

    static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        let first = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let second = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        guard let first, let second else { return false }
        return first.isEqual(second)
    }
}
