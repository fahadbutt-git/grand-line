import Foundation
import os

/// An item going into or out of the Trash through FileOperations, for the
/// Put Back ledger. Every item FileOperations sends to the Trash is reported
/// (a Trash, a redo of one, a replaced item, a half copy, an undone copy), and
/// so is every item it takes out again.
public enum TrashChange: Sendable, Equatable {
    /// Went to the Trash from `original`; `stamp` tells it from a later item
    /// that takes the same name there.
    case trashed(original: URL, trashed: URL, stamp: FileStamp?)
    /// Left the Trash (Undo, Redo or Put Back took it out).
    case left(trashed: URL)
}

/// Copy, move, duplicate, rename, Rename N Items, new folder, move to Trash and
/// Put Back, each undoable and redoable.
/// Nothing is ever deleted outright: replaced items and undone copies go to the
/// Trash, a move to another volume sends the original to the Trash once the
/// copy is complete, and a half copied item goes to the Trash.
/// Operations run one at a time, in the order asked, the way Nimble Commander
/// queues them (`FileTaskQueue` runs them as tasks). Each stops between files
/// when its task is cancelled; what it finished stays undoable.
/// Places are compared by what they reach (`FileIdentity`), not by how their
/// paths are spelled, so a link such as ~/Drive is the folder it points to.
public actor FileOperations {
    /// Moves an item to the Trash and returns where it went.
    public typealias Trash = @Sendable (URL) throws -> URL

    public static let systemTrash: Trash = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
    }

    static let log = Logger(subsystem: "com.grandline.nexus", category: "files")

    /// Progress of the running operation. One reader at a time.
    public nonisolated let progress: AsyncStream<OperationProgress>
    private let progressContinuation: AsyncStream<OperationProgress>.Continuation
    /// Items into and out of the Trash, for Put Back. One reader at a time.
    public nonisolated let trashChanges: AsyncStream<TrashChange>
    private let trashContinuation: AsyncStream<TrashChange>.Continuation
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
        let (changes, changesContinuation) = AsyncStream.makeStream(of: TrashChange.self, bufferingPolicy: .unbounded)
        self.trashChanges = changes
        self.trashContinuation = changesContinuation
        self.trash = trash
    }

    deinit {
        progressContinuation.finish()
        trashContinuation.finish()
    }

    // MARK: Operations

    /// Copies items into a folder. Copying into the items' own folder keeps both.
    @discardableResult
    public func copy(_ items: [URL], to folder: URL, conflict: ConflictPolicy = .keepBoth) throws -> [URL] {
        try copy(items, to: folder, resolution: ConflictResolution(conflict))
    }

    /// Copies items into a folder, each taken name settled as `resolution` says.
    @discardableResult
    public func copy(_ items: [URL], to folder: URL, resolution: ConflictResolution) throws -> [URL] {
        try copySteps(plan(items, into: folder, resolution: resolution, moving: false), kind: .copy)
    }

    /// Moves items into a folder. Items already there are left alone.
    @discardableResult
    public func move(_ items: [URL], to folder: URL, conflict: ConflictPolicy = .keepBoth) throws -> [URL] {
        try move(items, to: folder, resolution: ConflictResolution(conflict))
    }

    /// Moves items into a folder, each taken name settled as `resolution` says.
    @discardableResult
    public func move(_ items: [URL], to folder: URL, resolution: ConflictResolution) throws -> [URL] {
        try moveSteps(plan(items, into: folder, resolution: resolution, moving: true), kind: .move)
    }

    /// The items whose names are already taken in `folder`, for the conflict
    /// sheet to ask about before the task starts. Items already in `folder`
    /// (by any path to it) are not conflicts: copying keeps both and moving
    /// leaves them.
    public static func conflicts(_ items: [URL], in folder: URL) -> [FileConflict] {
        var found: [FileConflict] = []
        var seen = Set<String>()
        var parents: [String: Bool] = [:]
        for item in items {
            let name = item.lastPathComponent
            let key = FileIdentity.nameKey(name)
            guard !seen.contains(key) else { continue }
            let parent = item.deletingLastPathComponent()
            let sameFolder = parents[parent.path] ?? FileIdentity.sameFolder(parent, folder)
            parents[parent.path] = sameFolder
            guard !sameFolder else { continue }
            seen.insert(key)
            let existing = folder.appendingPathComponent(name)
            if FileTree.exists(existing), !FileIdentity.sameItem(item, existing) {
                found.append(FileConflict(source: item, existing: existing))
            }
        }
        return found
    }

    private func moveSteps(_ steps: [Step], kind: FileOperationKind) throws -> [URL] {
        var moves: [UndoRecord.Move] = []
        var replaced: [UndoRecord.Move] = []
        report(kind, done: 0, of: steps.count, current: steps.first?.source)
        do {
            for (i, step) in steps.enumerated() {
                try Task.checkCancellation()
                let destination = try settledDestination(for: step, replaced: &replaced)
                if FileIdentity.sameVolume(step.source, destination.deletingLastPathComponent()) {
                    try place(step.source, at: destination)
                } else {
                    // Another volume: copied with progress, so Stop works
                    // mid-item and a half copy goes to the Trash; the original
                    // goes to the Trash only once the copy is complete.
                    try moveAcrossVolumes(step.source, to: destination) { file, _ in
                        report(kind, done: i, of: steps.count, current: file)
                        try Task.checkCancellation()
                    }
                }
                moves.append(.init(from: step.source, to: destination))
                if kind == .putBack { trashContinuation.yield(.left(trashed: step.source)) }
                report(kind, done: i + 1, of: steps.count, current: i + 1 < steps.count ? steps[i + 1].source : nil)
            }
        } catch {
            finishEarly(kind, done: moves.count, of: steps.count)
            if !moves.isEmpty || !replaced.isEmpty {
                push(UndoRecord(kind: kind, action: .moved(moves), replaced: replaced))
            }
            throw error
        }
        push(UndoRecord(kind: kind, action: .moved(moves), replaced: replaced))
        return moves.map(\.to)
    }

    /// Where a planned step really goes, decided as it starts: a replaced item
    /// goes to the Trash now, and a name something else took since the plan
    /// was made gets a keep-both name instead of being written over.
    private func settledDestination(for step: Step, replaced: inout [UndoRecord.Move]) throws -> URL {
        let destination = step.destination
        guard FileTree.exists(destination), !FileIdentity.sameItem(step.source, destination) else { return destination }
        if step.replaces {
            replaced.append(.init(from: destination, to: try sendToTrash(destination)))
            return destination
        }
        let folder = destination.deletingLastPathComponent()
        return folder.appendingPathComponent(FileNaming.keepBoth(destination.lastPathComponent, in: folder))
    }

    /// Put Back: each item leaves the Trash for where it was, under its old
    /// name, or "name 2" when something new took the name. One undo record.
    @discardableResult
    public func putBack(_ items: [(item: URL, original: URL)]) throws -> [URL] {
        var steps: [Step] = []
        var taken: [String: Set<String>] = [:]
        for entry in items {
            guard FileTree.exists(entry.item) else { throw FileOperationError.missing(entry.item) }
            let folder = entry.original.deletingLastPathComponent()
            let key = FileIdentity.resolved(folder).path
            let name = FileNaming.available(entry.original.lastPathComponent, in: folder, avoiding: taken[key] ?? [])
            taken[key, default: []].insert(name)
            steps.append(Step(source: entry.item, destination: folder.appendingPathComponent(name), replaces: false))
        }
        return try moveSteps(steps, kind: .putBack)
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
        try place(item, at: destination)
        push(UndoRecord(kind: .rename, action: .renamed(.init(from: item, to: destination)), replaced: []))
        return destination
    }

    /// Rename N Items: every item gets its new name in one step that Undo
    /// reverses at once. Names may swap ("a" to "b" and "b" to "a"). Fails, and
    /// renames nothing, when a name is invalid, two items would share a name, or
    /// a name belongs to an item that is not being renamed. Returns the items'
    /// new places, in order.
    @discardableResult
    public func renameItems(_ items: [(item: URL, name: String)]) throws -> [URL] {
        var moves: [UndoRecord.Move] = []
        var results: [URL] = []
        var targets: [String: String] = [:]
        var duplicates: [String] = []
        let sources = Set(items.map { $0.item.standardizedFileURL.path.lowercased() })
        for entry in items {
            guard FileNaming.isValid(entry.name) else { throw FileOperationError.invalidName(entry.name) }
            guard FileTree.exists(entry.item) else { throw FileOperationError.missing(entry.item) }
            let destination = entry.item.deletingLastPathComponent().appendingPathComponent(entry.name)
            let key = destination.standardizedFileURL.path.lowercased()
            if targets[key] != nil { duplicates.append(entry.name) }
            targets[key] = entry.name
            results.append(destination)
            if entry.name == entry.item.lastPathComponent { continue }
            if FileTree.exists(destination), !sources.contains(key), !Self.isSameItem(entry.item, destination) {
                throw FileOperationError.nameTaken(entry.name)
            }
            moves.append(.init(from: entry.item, to: destination))
        }
        guard duplicates.isEmpty else { throw FileOperationError.duplicateNames(duplicates) }
        guard !moves.isEmpty else { return results }
        try Task.checkCancellation()
        report(.renameItems, done: 0, of: moves.count, current: moves.first?.from)
        try Self.placeAll(moves)
        report(.renameItems, done: moves.count, of: moves.count, current: nil)
        push(UndoRecord(kind: .renameItems, action: .renamedMany(moves), replaced: []))
        return results
    }

    /// Records items made outside FileOperations (an archive by Compress, items
    /// by Extract), so Undo moves them to the Trash like copies.
    public func recordCreated(_ items: [URL], kind: FileOperationKind) {
        guard !items.isEmpty else { return }
        push(UndoRecord(kind: kind, action: .created(items), replaced: []))
    }

    /// A half-made item of Nexus's own (a stopped Compress or Extract, a drop
    /// that did not finish) goes to the Trash, never deleted outright.
    public func discard(_ item: URL) {
        guard FileTree.exists(item) else { return }
        do {
            _ = try sendToTrash(item)
        } catch {
            Self.log.error("could not move \(item.path, privacy: .public) to the Trash: \(String(describing: error), privacy: .public)")
        }
    }

    /// A hidden working folder of Nexus's own (where file promises were
    /// written): removed when nothing is left in it, otherwise to the Trash
    /// with what is still inside.
    public func discardWorkingFolder(_ folder: URL) {
        guard FileTree.exists(folder) else { return }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [""]
        if left.isEmpty, (try? FileManager.default.removeItem(at: folder)) != nil { return }
        discard(folder)
    }

    /// Items received from another app (a file promise from Mail, Photos or
    /// an archive pane) into `staging`, a folder beside `folder` on its
    /// volume: each moves into `folder` under a free name, and Undo moves them
    /// to the Trash like copies.
    @discardableResult
    public func adopt(_ items: [URL], into folder: URL, kind: FileOperationKind = .copy) throws -> [URL] {
        var made: [URL] = []
        var taken = Set<String>()
        do {
            for item in items {
                try Task.checkCancellation()
                let name = FileNaming.available(item.lastPathComponent, in: folder, avoiding: taken)
                taken.insert(name)
                let destination = folder.appendingPathComponent(name)
                try place(item, at: destination)
                made.append(destination)
            }
        } catch {
            recordCreated(made, kind: kind)
            throw error
        }
        recordCreated(made, kind: kind)
        return made
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

    /// Returns where each item went in the Trash. Each item is reported to
    /// `trashChanges` as it goes, so Put Back knows it even when the task
    /// stops halfway.
    @discardableResult
    public func moveToTrash(_ items: [URL]) throws -> [URL] {
        var moves: [UndoRecord.Move] = []
        report(.trash, done: 0, of: items.count, current: items.first)
        do {
            for (i, item) in items.enumerated() {
                try Task.checkCancellation()
                moves.append(.init(from: item, to: try sendToTrash(item)))
                report(.trash, done: i + 1, of: items.count, current: i + 1 < items.count ? items[i + 1] : nil)
            }
        } catch {
            finishEarly(.trash, done: moves.count, of: items.count)
            if !moves.isEmpty { push(UndoRecord(kind: .trash, action: .trashed(moves), replaced: [])) }
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

    /// What Undo can reverse, newest first, for the tasks popover.
    public var history: [OperationRecord] { undoStack.reversed().map(\.summary) }

    /// Undoes the last `steps` operations, newest first, stopping early when
    /// there is no more to undo. Returns what was undone.
    @discardableResult
    public func undo(steps: Int) throws -> [FileOperationKind] {
        var undone: [FileOperationKind] = []
        for _ in 0..<max(0, steps) {
            guard let kind = try undo() else { break }
            undone.append(kind)
        }
        return undone
    }

    /// An undo or redo that stopped partway: what it did and what is left.
    private struct UndoPartial: Error {
        let done: RedoRecord.Action?
        let left: UndoRecord.Action
        let error: Error
    }

    private struct RedoPartial: Error {
        let done: UndoRecord.Action?
        let left: RedoRecord.Action
        let error: Error
    }

    /// Reverses the last operation. Returns what was undone, nil when there was nothing.
    /// When a step fails partway (an item renamed or taken away since), what
    /// was reversed becomes a Redo and what was not stays the top Undo, so
    /// neither half is forgotten.
    @discardableResult
    public func undo() throws -> FileOperationKind? {
        guard let record = undoStack.popLast() else { return nil }
        let action: RedoRecord.Action
        do {
            action = try reverse(record)
        } catch let partial as UndoPartial {
            if let done = partial.done { pushRedo(RedoRecord(kind: record.kind, action: done, replaced: [])) }
            push(UndoRecord(kind: record.kind, action: partial.left, replaced: record.replaced, date: record.date), clearingRedo: false)
            throw partial.error
        } catch {
            push(record, clearingRedo: false)
            throw error
        }
        var replaced: [URL] = []
        let pending = Array(record.replaced.reversed())
        for (i, item) in pending.enumerated() {
            do {
                let spot = Self.freeSpot(for: item.from)
                try place(item.to, at: spot)
                trashContinuation.yield(.left(trashed: item.to))
                replaced.append(spot)
            } catch {
                pushRedo(RedoRecord(kind: record.kind, action: action, replaced: replaced))
                let left = Array(pending[i...].reversed())
                push(UndoRecord(kind: record.kind, action: .created([]), replaced: left, date: record.date), clearingRedo: false)
                throw error
            }
        }
        pushRedo(RedoRecord(kind: record.kind, action: action, replaced: replaced))
        return record.kind
    }

    private func reverse(_ record: UndoRecord) throws -> RedoRecord.Action {
        switch record.action {
        case .created(let items):
            var trashed: [UndoRecord.Move] = []
            let ordered = Array(items.reversed())
            for (i, item) in ordered.enumerated() where FileTree.exists(item) {
                do {
                    trashed.append(.init(from: item, to: try sendToTrash(item)))
                } catch {
                    throw UndoPartial(done: trashed.isEmpty ? nil : .restore(trashed),
                                      left: .created(Array(ordered[i...].reversed())), error: error)
                }
            }
            return .restore(trashed)
        case .moved(let moves):
            var back: [UndoRecord.Move] = []
            let ordered = Array(moves.reversed())
            for (i, move) in ordered.enumerated() {
                do {
                    let spot = Self.freeSpot(for: move.from)
                    try place(move.to, at: spot)
                    if record.kind == .putBack {
                        // Back into the Trash: Put Back works for it again.
                        trashContinuation.yield(.trashed(original: move.to, trashed: spot, stamp: FileStamp.of(spot)))
                    }
                    back.append(.init(from: spot, to: move.to))
                } catch {
                    throw UndoPartial(done: back.isEmpty ? nil : .move(back),
                                      left: .moved(Array(ordered[i...].reversed())), error: error)
                }
            }
            return .move(back)
        case .trashed(let moves):
            var restored: [URL] = []
            let ordered = Array(moves.reversed())
            for (i, move) in ordered.enumerated() {
                do {
                    let spot = Self.freeSpot(for: move.from)
                    try place(move.to, at: spot)
                    trashContinuation.yield(.left(trashed: move.to))
                    restored.append(spot)
                } catch {
                    throw UndoPartial(done: restored.isEmpty ? nil : .trash(restored),
                                      left: .trashed(Array(ordered[i...].reversed())), error: error)
                }
            }
            return .trash(restored)
        case .renamed(let move):
            do {
                // The old name may have been taken since: never put one item over another.
                if FileTree.exists(move.from), !Self.isSameItem(move.to, move.from) {
                    throw FileOperationError.nameTaken(move.from.lastPathComponent)
                }
                try place(move.to, at: move.from)
            } catch {
                throw UndoPartial(done: nil, left: .renamed(move), error: error)
            }
            return .rename(move)
        case .renamedMany(let moves):
            do {
                try Self.placeAll(moves.map { UndoRecord.Move(from: $0.to, to: $0.from) })
            } catch {
                throw UndoPartial(done: nil, left: .renamedMany(moves), error: error)
            }
            return .renameMany(moves)
        }
    }

    /// Does the last undone operation again, and makes it undoable once more.
    /// Returns what was redone, nil when there was nothing. A redo that fails
    /// partway keeps both halves, as Undo does.
    @discardableResult
    public func redo() throws -> FileOperationKind? {
        guard let record = redoStack.popLast() else { return nil }
        var replaced: [UndoRecord.Move] = []
        let pending = record.replaced.filter { FileTree.exists($0) }
        for (i, item) in pending.enumerated() {
            do {
                replaced.append(.init(from: item, to: try sendToTrash(item)))
            } catch {
                if !replaced.isEmpty { push(UndoRecord(kind: record.kind, action: .created([]), replaced: replaced), clearingRedo: false) }
                pushRedo(RedoRecord(kind: record.kind, action: record.action, replaced: Array(pending[i...])))
                throw error
            }
        }
        let action: UndoRecord.Action
        do {
            action = try reapply(record)
        } catch let partial as RedoPartial {
            if partial.done != nil || !replaced.isEmpty {
                push(UndoRecord(kind: record.kind, action: partial.done ?? .created([]), replaced: replaced), clearingRedo: false)
            }
            pushRedo(RedoRecord(kind: record.kind, action: partial.left, replaced: []))
            throw partial.error
        } catch {
            if !replaced.isEmpty { push(UndoRecord(kind: record.kind, action: .created([]), replaced: replaced), clearingRedo: false) }
            pushRedo(RedoRecord(kind: record.kind, action: record.action, replaced: []))
            throw error
        }
        push(UndoRecord(kind: record.kind, action: action, replaced: replaced), clearingRedo: false)
        return record.kind
    }

    private func reapply(_ record: RedoRecord) throws -> UndoRecord.Action {
        switch record.action {
        case .restore(let moves):
            var created: [URL] = []
            let ordered = Array(moves.reversed())
            for (i, move) in ordered.enumerated() {
                do {
                    let spot = Self.freeSpot(for: move.from)
                    try place(move.to, at: spot)
                    trashContinuation.yield(.left(trashed: move.to))
                    created.append(spot)
                } catch {
                    throw RedoPartial(done: created.isEmpty ? nil : .created(created),
                                      left: .restore(Array(ordered[i...].reversed())), error: error)
                }
            }
            return .created(created)
        case .move(let moves):
            var done: [UndoRecord.Move] = []
            let ordered = Array(moves.reversed())
            for (i, move) in ordered.enumerated() {
                do {
                    let spot = Self.freeSpot(for: move.to)
                    try place(move.from, at: spot)
                    if record.kind == .putBack { trashContinuation.yield(.left(trashed: move.from)) }
                    done.append(.init(from: move.from, to: spot))
                } catch {
                    throw RedoPartial(done: done.isEmpty ? nil : .moved(done),
                                      left: .move(Array(ordered[i...].reversed())), error: error)
                }
            }
            return .moved(done)
        case .rename(let move):
            do {
                if FileTree.exists(move.to), !Self.isSameItem(move.from, move.to) {
                    throw FileOperationError.nameTaken(move.to.lastPathComponent)
                }
                try place(move.from, at: move.to)
            } catch {
                throw RedoPartial(done: nil, left: .rename(move), error: error)
            }
            return .renamed(move)
        case .renameMany(let moves):
            do {
                let sources = Set(moves.map { $0.from.standardizedFileURL.path.lowercased() })
                for move in moves where FileTree.exists(move.to) && !sources.contains(move.to.standardizedFileURL.path.lowercased())
                    && !Self.isSameItem(move.from, move.to) {
                    throw FileOperationError.nameTaken(move.to.lastPathComponent)
                }
                try Self.placeAll(moves)
            } catch {
                throw RedoPartial(done: nil, left: .renameMany(moves), error: error)
            }
            return .renamedMany(moves)
        case .trash(let items):
            var trashed: [UndoRecord.Move] = []
            for (i, item) in items.enumerated() {
                do {
                    trashed.append(.init(from: item, to: try sendToTrash(item)))
                } catch {
                    throw RedoPartial(done: trashed.isEmpty ? nil : .trashed(trashed), left: .trash(Array(items[i...])), error: error)
                }
            }
            return .trashed(trashed)
        }
    }

    // MARK: Helpers

    func plan(_ items: [URL], into folder: URL, conflict: ConflictPolicy, moving: Bool) throws -> [Step] {
        try plan(items, into: folder, resolution: ConflictResolution(conflict), moving: moving)
    }

    func plan(_ items: [URL], into folder: URL, resolution: ConflictResolution, moving: Bool) throws -> [Step] {
        var steps: [Step] = []
        // Names compared without case, as the volume compares them: "Notes"
        // and "notes" never both go to one folder under one name.
        var taken = Set<String>()
        let ancestry = FileIdentity.Ancestry(folder)
        var parents: [String: Bool] = [:]
        // Every source and every folder above one, worked out on the first Replace.
        var sourceLines: Set<FileStamp>?
        for item in items {
            guard FileTree.exists(item) else { throw FileOperationError.missing(item) }
            // A folder into itself or a folder inside it, by any path (a link
            // to it, a firmlink): refused, or the copy would never end.
            if FileTree.isRealFolder(item), ancestry.holds(item) { throw FileOperationError.intoItself(item) }
            let name = item.lastPathComponent
            let parent = item.deletingLastPathComponent()
            let sameFolder: Bool
            if let known = parents[parent.path] {
                sameFolder = known
            } else {
                sameFolder = FileIdentity.sameFolder(parent, folder)
                parents[parent.path] = sameFolder
            }
            if moving && sameFolder { continue }
            var destination = folder.appendingPathComponent(name)
            var replaces = false
            if taken.contains(FileIdentity.nameKey(name)) || sameFolder {
                destination = folder.appendingPathComponent(FileNaming.keepBoth(name, in: folder, avoiding: taken))
            } else if FileTree.exists(destination) {
                if FileIdentity.sameItem(item, destination) {
                    // The item is already there, reached by another path:
                    // moving leaves it, copying keeps both. Never Replace,
                    // which would send the source itself to the Trash.
                    if moving { continue }
                    destination = folder.appendingPathComponent(FileNaming.keepBoth(name, in: folder, avoiding: taken))
                } else {
                    switch resolution.policy(for: name) {
                    case .skip:
                        continue
                    case .keepBoth:
                        destination = folder.appendingPathComponent(FileNaming.keepBoth(name, in: folder, avoiding: taken))
                    case .replace:
                        // The item to be replaced is a source or holds one.
                        if sourceLines == nil { sourceLines = Set(items.flatMap { FileIdentity.Ancestry($0).stamps }) }
                        if let stamp = FileStamp.of(destination, followingLink: true), sourceLines?.contains(stamp) == true {
                            throw FileOperationError.replacesSource(destination)
                        }
                        replaces = true
                    }
                }
            }
            taken.insert(FileIdentity.nameKey(destination.lastPathComponent))
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
        var partial: URL?
        do {
            for step in steps {
                try Task.checkCancellation()
                let destination = try settledDestination(for: step, replaced: &replaced)
                // The destination is free now: whatever is there after a
                // failure was made by this copy, and only that is cleaned up.
                var made = false
                let existedBefore = FileTree.exists(destination)
                do {
                    try FileTree.copy(step.source, to: destination, created: { made = true }) { file, size in
                        files += 1
                        bytes += size
                        report(kind, files: files, of: totalFiles, bytes: bytes, of: totalBytes, current: file)
                        try Task.checkCancellation()
                    }
                } catch {
                    if made || (!existedBefore && FileTree.exists(destination)) { partial = destination }
                    throw error
                }
                created.append(destination)
            }
        } catch {
            // A copy stopped halfway leaves no half item behind: it goes to the Trash.
            if let partial { discard(partial) }
            finishEarly(kind, done: files, of: totalFiles, bytes: bytes, of: totalBytes)
            if !created.isEmpty || !replaced.isEmpty {
                push(UndoRecord(kind: kind, action: .created(created), replaced: replaced))
            }
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

    private func pushRedo(_ record: RedoRecord) {
        redoStack.append(record)
        if redoStack.count > Self.undoLimit { redoStack.removeFirst() }
    }

    /// Every item FileOperations sends to the Trash goes through here, so the
    /// Put Back ledger hears of each one.
    private func sendToTrash(_ item: URL) throws -> URL {
        let trashed = try trash(item)
        trashContinuation.yield(.trashed(original: item, trashed: trashed, stamp: FileStamp.of(trashed)))
        return trashed
    }

    /// A stopped or failed operation reports itself finished at what it did,
    /// so the progress shown never stays on a task that has ended.
    private func finishEarly(_ kind: FileOperationKind, done: Int, of total: Int, bytes: Int64 = 0, of totalBytes: Int64 = 0) {
        report(kind, files: done, of: done, bytes: bytes, of: bytes, current: nil)
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

    /// Moves an item: a rename on one volume (a change of case only, "a.txt"
    /// to "A.txt", included), a copy and then the original to the Trash
    /// across volumes. Never puts one item over another.
    func place(_ source: URL, at destination: URL) throws {
        if Self.isCaseOnly(source, destination) {
            try Self.renameCaseOnly(source, to: destination)
        } else if !FileIdentity.sameVolume(source, destination.deletingLastPathComponent()) {
            try moveAcrossVolumes(source, to: destination) { _, _ in try Task.checkCancellation() }
        } else {
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }

    /// A move to another volume, done as Finder does it but without deleting:
    /// the item is copied (metadata and quarantine included), a half copy goes
    /// to the Trash, and the original goes to the Trash only once the copy is
    /// complete.
    func moveAcrossVolumes(_ source: URL, to destination: URL, onFile: (URL, Int64) throws -> Void) throws {
        guard !FileTree.exists(destination) else { throw FileOperationError.nameTaken(destination.lastPathComponent) }
        var made = false
        do {
            try FileTree.copy(source, to: destination, created: { made = true }, onFile: onFile)
        } catch {
            if made || FileTree.exists(destination) { discard(destination) }
            throw error
        }
        do {
            _ = try sendToTrash(source)
        } catch {
            // Both stay: the move is kept, and the original is still where it was.
            Self.log.error("moved \(source.path, privacy: .public) to another volume, but the original could not go to the Trash: \(String(describing: error), privacy: .public)")
        }
    }

    static func isCaseOnly(_ source: URL, _ destination: URL) -> Bool {
        source.lastPathComponent != destination.lastPathComponent
            && FileIdentity.nameKey(source.lastPathComponent) == FileIdentity.nameKey(destination.lastPathComponent)
            && FileIdentity.sameFolder(source.deletingLastPathComponent(), destination.deletingLastPathComponent())
    }

    /// "a.txt" to "A.txt": through a hidden name beside it, because a rename
    /// to a name the volume sees as the same is refused. When the second step
    /// fails (another "A.txt" on a volume that tells case apart), the item goes
    /// back to its old name, so it is never left under the hidden one.
    static func renameCaseOnly(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if FileTree.exists(destination), !isSameItem(source, destination) {
            throw FileOperationError.nameTaken(destination.lastPathComponent)
        }
        let temporary = source.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
        try fileManager.moveItem(at: source, to: temporary)
        do {
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            do {
                try fileManager.moveItem(at: temporary, to: source)
            } catch let rollback {
                log.fault("rename of \(source.path, privacy: .public) failed and it could not go back; it is at \(temporary.path, privacy: .public): \(String(describing: rollback), privacy: .public)")
            }
            throw error
        }
    }

    /// Moves several items at once through hidden names beside them, so names
    /// can swap. On a failure every item goes back where it was; one that
    /// cannot is logged with the hidden name it is under.
    static func placeAll(_ moves: [UndoRecord.Move]) throws {
        let fileManager = FileManager.default
        var parked: [(move: UndoRecord.Move, temporary: URL)] = []
        var placed: [(move: UndoRecord.Move, temporary: URL)] = []
        do {
            // A name another item took since (not one of those being renamed):
            // refused before anything moves.
            let sources = Set(moves.compactMap { FileStamp.of($0.from) })
            for move in moves {
                if let there = FileStamp.of(move.to), !sources.contains(there) {
                    throw FileOperationError.nameTaken(move.to.lastPathComponent)
                }
            }
            for move in moves {
                let temporary = move.from.deletingLastPathComponent().appendingPathComponent(".rename-\(UUID().uuidString)")
                try fileManager.moveItem(at: move.from, to: temporary)
                parked.append((move, temporary))
            }
            for entry in parked {
                try fileManager.moveItem(at: entry.temporary, to: entry.move.to)
                placed.append(entry)
            }
        } catch {
            for entry in placed.reversed() {
                do {
                    try fileManager.moveItem(at: entry.move.to, to: entry.temporary)
                } catch let rollback {
                    log.fault("rename rollback: \(entry.move.to.path, privacy: .public) could not be parked again: \(String(describing: rollback), privacy: .public)")
                }
            }
            for entry in parked.reversed() where FileTree.exists(entry.temporary) {
                do {
                    try fileManager.moveItem(at: entry.temporary, to: entry.move.from)
                } catch let rollback {
                    log.fault("rename rollback: \(entry.move.from.path, privacy: .public) is still at \(entry.temporary.path, privacy: .public): \(String(describing: rollback), privacy: .public)")
                }
            }
            throw error
        }
    }

    /// The original place, or a keep-both name beside it when something new is there.
    static func freeSpot(for url: URL) -> URL {
        guard FileTree.exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        return folder.appendingPathComponent(FileNaming.keepBoth(url.lastPathComponent, in: folder))
    }

    static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        FileIdentity.sameItem(a, b)
    }
}
