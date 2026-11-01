import Foundation
import LauncherKit
import QueryKit

/// Runs a QueryKit query with NSMetadataQuery and returns the paths that pass
/// its folder post-filter. Stops early when cancelled or after `timeout`,
/// with what was gathered so far.
///
/// The query runs on its own serial operation queue, not the main thread:
/// starting it, gathering, and reading each result's attributes all wait on
/// Spotlight, which on a busy or slow disk takes long enough to be felt.
final class SpotlightSearch: Sendable {
    let timeout: TimeInterval = 3

    func run(_ text: String, limit: Int, savedSearch: @escaping @Sendable (String) -> String?) async -> [FileHit] {
        let compiled = SpotlightCompiler.compile(QueryParser.parse(text), savedSearch: savedSearch)
        let search = MetadataSearch(compiled: compiled, limit: limit)
        let timeout = self.timeout
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[FileHit], Never>) in
                search.start(continuation, timeout: timeout)
            }
        } onCancel: {
            search.cancel()
        }
    }
}

/// One NSMetadataQuery from start to its single answer. Everything that
/// touches the query runs on `queue`, the query's own operation queue.
final class MetadataSearch: @unchecked Sendable {
    let query = NSMetadataQuery()
    let compiled: SpotlightQuery
    let limit: Int
    private let queue: OperationQueue
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[FileHit], Never>?
    /// Cancelled before it started: it answers at once with nothing.
    private var cancelled = false
    private var observer: NSObjectProtocol?

    init(compiled: SpotlightQuery, limit: Int) {
        self.compiled = compiled
        self.limit = limit
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        queue.name = "Sight.Spotlight"
        query.operationQueue = queue
        query.predicate = compiled.predicate
        query.searchScopes = compiled.scopes.isEmpty ? [NSMetadataQueryUserHomeScope] : compiled.scopes
        if let sort = compiled.sort {
            query.sortDescriptors = [NSSortDescriptor(key: sort.attribute, ascending: sort.ascending)]
        }
    }

    func start(_ continuation: CheckedContinuation<[FileHit], Never>, timeout: TimeInterval) {
        lock.lock()
        let stopNow = cancelled
        if !stopNow { self.continuation = continuation }
        lock.unlock()
        if stopNow {
            continuation.resume(returning: [])
            return
        }
        queue.addOperation { [self] in
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: queue) { [weak self] _ in
                self?.finish()
            }
            if !query.start() { finish() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.queue.addOperation { self.finish() }
        }
    }

    /// The task was cancelled: answer with what was gathered.
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        queue.addOperation { [self] in finish() }
    }

    /// Answers once; later calls do nothing. Runs on `queue`.
    private func finish() {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        guard let waiting else { return }
        query.disableUpdates()
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        var hits: [FileHit] = []
        for i in 0..<query.resultCount where hits.count < limit {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  compiled.postFilter(path) else { continue }
            let type = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            hits.append(FileHit(path: path, isFolder: type == "public.folder", modified: modified))
        }
        waiting.resume(returning: hits)
    }
}
