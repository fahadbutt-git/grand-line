import Foundation
import LauncherKit
import QueryKit

/// Runs a QueryKit query with NSMetadataQuery on the main thread and returns the
/// paths that pass its folder post-filter. Stops early when cancelled or after
/// `timeout`, with what was gathered so far.
@MainActor
final class SpotlightSearch {
    let timeout: TimeInterval = 3

    func run(_ text: String, limit: Int, savedSearch: @escaping @Sendable (String) -> String?) async -> [FileHit] {
        let compiled = SpotlightCompiler.compile(QueryParser.parse(text), savedSearch: savedSearch)
        let search = MetadataSearch(compiled: compiled, limit: limit)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[FileHit], Never>) in
                search.start(continuation, timeout: timeout)
            }
        } onCancel: {
            Task { @MainActor in search.finish() }
        }
    }
}

/// One NSMetadataQuery from start to its single answer.
@MainActor
final class MetadataSearch {
    let query = NSMetadataQuery()
    let compiled: SpotlightQuery
    let limit: Int
    private var continuation: CheckedContinuation<[FileHit], Never>?
    private var observer: NSObjectProtocol?

    init(compiled: SpotlightQuery, limit: Int) {
        self.compiled = compiled
        self.limit = limit
        query.predicate = compiled.predicate
        query.searchScopes = compiled.scopes.isEmpty ? [NSMetadataQueryUserHomeScope] : compiled.scopes
        if let sort = compiled.sort {
            query.sortDescriptors = [NSSortDescriptor(key: sort.attribute, ascending: sort.ascending)]
        }
    }

    func start(_ continuation: CheckedContinuation<[FileHit], Never>, timeout: TimeInterval) {
        self.continuation = continuation
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        if !query.start() { finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    /// Answers once; later calls do nothing.
    func finish() {
        guard let continuation else { return }
        self.continuation = nil
        query.disableUpdates()
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        var hits: [FileHit] = []
        for i in 0..<query.resultCount where hits.count < limit {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  compiled.postFilter(path) else { continue }
            let type = item.value(forAttribute: NSMetadataItemContentTypeKey) as? String
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            hits.append(FileHit(path: path, isFolder: type == "public.folder", modified: modified))
        }
        continuation.resume(returning: hits)
    }
}
