import AppKit
import BrowserKit
import FileKit
import IndexKit

/// The sidebar's sections, rebuilt when a volume mounts or unmounts, a saved
/// search changes, or something new lands in Downloads.
@MainActor
final class SidebarModel: ObservableObject {
    @Published private(set) var groups: [SidebarGroup] = []
    private unowned let services: Services
    private var downloadsWatcher: FolderWatcher?
    private var downloadsTask: Task<Void, Never>?
    private static let visitedKey = "DownloadsVisited"

    init(services: Services) {
        self.services = services
    }

    var downloads: URL { services.paths.home.appendingPathComponent("Downloads", isDirectory: true) }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        let watcher = FolderWatcher(paths: [downloads.path], latency: 1)
        if watcher.start() {
            downloadsWatcher = watcher
            let changes = watcher.changes
            downloadsTask = Task { [weak self] in
                for await _ in changes { self?.noteDownloads() }
            }
        }
        refresh()
    }

    func refresh() {
        groups = SidebarBuilder.build(input())
    }

    /// Every section and item, hidden ones too, in the chosen order (Settings, Sidebar).
    func everything() -> [SidebarGroup] {
        SidebarBuilder.everything(input())
    }

    private func input() -> SidebarBuilder.Input {
        let paths = services.paths
        let drives = GoogleDrive.accounts(home: paths.home)
        let settings = services.settings
        return SidebarBuilder.Input(
            home: paths.home,
            places: settings.placeURLs(home: paths.home) ?? SidebarBuilder.defaultPlaces(home: paths.home, drives: drives),
            projects: settings.projectURLs(home: paths.home, children: FolderReader.subfolderNames),
            savedSearches: services.savedSearches.names,
            volumes: VolumeInfo.mounted(),
            drives: drives,
            trash: paths.trash,
            newDownloads: newDownloads().count,
            hidden: services.sidebarHidden,
            layout: NexusPreferencesStore.shared.current.sidebar
        )
    }

    /// Visiting Downloads clears the "new" badge.
    func visited(_ folder: URL) {
        guard folder.standardizedFileURL == downloads.standardizedFileURL else { return }
        UserDefaults.standard.set(Date(), forKey: Self.visitedKey)
        refresh()
    }

    /// New downloads also go in Recents (R17).
    private func noteDownloads() {
        services.noteOpened(newDownloads())
        refresh()
    }

    private func newDownloads() -> [URL] {
        let since = UserDefaults.standard.object(forKey: Self.visitedKey) as? Date ?? Date()
        if UserDefaults.standard.object(forKey: Self.visitedKey) == nil {
            UserDefaults.standard.set(since, forKey: Self.visitedKey)
        }
        let items = (try? FolderReader.items(in: downloads, showHidden: false)) ?? []
        return items.filter { ($0.created ?? .distantPast) > since }.map(\.url)
    }
}
