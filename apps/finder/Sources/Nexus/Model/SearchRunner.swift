import AppKit
import BrowserKit
import FileKit
import IndexKit

/// Runs one search: IndexKit's name matches first (R1), then Spotlight through
/// QueryKit's predicate (R2), merged without moving what is already shown.
/// Spotlight's name matches lead the files it found only by their contents,
/// newest first, and results from app data (caches, ~/Library, hidden
/// folders, app bundles) are left out of both. Each result carries how it was
/// found (`SearchHits.ranks`), for relevance order and the "Found inside
/// files" section.
@MainActor
final class SearchRunner {
    private unowned let services: Services
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var nameTask: Task<Void, Never>?
    private var indexMatches: [IndexMatch] = []
    private var scanned: [String] = []
    private var spotlight: [String] = []

    init(services: Services) {
        self.services = services
    }

    /// - Parameters:
    ///   - content: whether plain words also match inside files (Settings'
    ///     "Include content matches", unless this search hides them).
    ///   - results: every time the results change, with the paths Spotlight
    ///     reported as changed since the last call (their rows are read again).
    func start(_ text: String, scope: SearchScope, content: Bool,
               results: @escaping (SearchHits, Set<String>) -> Void) {
        let saved = services.savedSearches
        let plan = SearchPlan.make(
            text, scope: scope, home: services.paths.home.path,
            drives: GoogleDrive.accounts(home: services.paths.home),
            savedSearch: { saved.query(named: $0) }, content: content
        )
        // Nothing to look for (an unknown @name, "kind:" while typing): the
        // predicate would match every file in the scope, so nothing is run.
        guard !plan.isUnconstrained else {
            results(SearchHits(), [])
            return
        }
        if let words = plan.nameText {
            let index = services.index
            // Only the scope's folders are searched, in the service.
            let folders = plan.scopes.filter { $0.hasPrefix("/") }
            let scope = folders.count == plan.scopes.count ? folders : nil
            // Folders the index leaves out (the Trash) are read from disk.
            let skipped = plan.foldersTheIndexSkips
            let plainWords = plan.words
            nameTask = Task { [weak self] in
                let matches = await index.search(words, limit: 400, scope: scope)
                var found: [String] = []
                if !skipped.isEmpty {
                    found = await Task.detached(priority: .userInitiated) {
                        FolderNameScan.paths(in: skipped, words: plainWords)
                    }.value
                }
                guard let self, !Task.isCancelled else { return }
                self.indexMatches = SearchResults.nameMatches(matches, plan: plan)
                self.scanned = found.filter { plan.accepts($0) && plan.keeps($0) }
                results(self.combined(plan), [])
            }
        }
        // Settings, Search: without content matches, Spotlight runs only for
        // queries the name index cannot answer (filters alone), and then
        // matches names only (the plan was compiled without content).
        if content || plan.nameText == nil {
            startSpotlight(plan, results: results)
        }
    }

    private func combined(_ plan: SearchPlan) -> SearchHits {
        SearchResults.combine(index: indexMatches, scanned: scanned, spotlight: spotlight, plan: plan)
    }

    private func startSpotlight(_ plan: SearchPlan, results: @escaping (SearchHits, Set<String>) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = plan.predicate
        query.searchScopes = plan.scopes
        // Newest first, so the files found inside that make the cut are the recent ones.
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.3
        let center = NotificationCenter.default
        let update: (Notification) -> Void = { [weak self] notification in
            let changed = SearchRunner.changedPaths(notification)
            MainActor.assumeIsolated {
                guard let self, let query = self.query else { return }
                query.disableUpdates()
                var paths: [String] = []
                // Content matches from app data are dropped below, so read past them.
                for i in 0..<min(query.resultCount, 10_000) {
                    if let item = query.result(at: i) as? NSMetadataItem,
                       let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                       plan.accepts(path) {
                        paths.append(path)
                    }
                }
                query.enableUpdates()
                self.spotlight = paths
                results(self.combined(plan), changed)
            }
        }
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: update),
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: update),
        ]
        self.query = query
        if !query.start() { results(combined(plan), []) }
    }

    /// Paths an update says were changed or removed, whose rows are read again.
    nonisolated static func changedPaths(_ notification: Notification) -> Set<String> {
        var paths = Set<String>()
        for key in [NSMetadataQueryUpdateChangedItemsKey, NSMetadataQueryUpdateRemovedItemsKey] {
            for item in notification.userInfo?[key] as? [NSMetadataItem] ?? [] {
                if let path = item.value(forAttribute: NSMetadataItemPathKey) as? String { paths.insert(path) }
            }
        }
        return paths
    }

    func stop() {
        nameTask?.cancel()
        query?.stop()
        query = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
