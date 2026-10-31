import AppKit
import BrowserKit
import FileKit
import IndexKit

/// Runs one search: IndexKit's name matches first (R1), then Spotlight through
/// QueryKit's predicate (R2), merged without moving what is already shown.
@MainActor
final class SearchRunner {
    private unowned let services: Services
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var nameTask: Task<Void, Never>?
    private var names: [String] = []

    init(services: Services) {
        self.services = services
    }

    func start(_ text: String, scope: SearchScope, results: @escaping ([String]) -> Void) {
        let saved = services.savedSearches
        let plan = SearchPlan.make(
            text, scope: scope, home: services.paths.home.path,
            drives: GoogleDrive.accounts(home: services.paths.home),
            savedSearch: { saved.query(named: $0) }
        )
        if let words = plan.nameText {
            let index = services.index
            nameTask = Task { [weak self] in
                let matches = await index.search(words, limit: 400)
                guard let self, !Task.isCancelled else { return }
                self.names = SearchResults.names(matches, plan: plan)
                results(self.names)
            }
        }
        startSpotlight(plan, results: results)
    }

    private func startSpotlight(_ plan: SearchPlan, results: @escaping ([String]) -> Void) {
        let query = NSMetadataQuery()
        query.predicate = plan.predicate
        query.searchScopes = plan.scopes
        query.notificationBatchingInterval = 0.3
        let center = NotificationCenter.default
        let update: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let query = self.query else { return }
                query.disableUpdates()
                var paths: [String] = []
                for i in 0..<min(query.resultCount, 2_000) {
                    if let item = query.result(at: i) as? NSMetadataItem,
                       let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                       plan.accepts(path) {
                        paths.append(path)
                    }
                }
                query.enableUpdates()
                results(SearchResults.merge(names: self.names, spotlight: paths))
            }
        }
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main, using: update),
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main, using: update),
        ]
        self.query = query
        if !query.start() { results(names) }
    }

    func stop() {
        nameTask?.cancel()
        query?.stop()
        query = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}
