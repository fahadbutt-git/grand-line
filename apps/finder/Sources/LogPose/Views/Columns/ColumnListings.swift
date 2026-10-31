import AppKit
import BrowserKit
import IndexKit

/// The column view's listings, one per folder. Each folder is read once in the
/// background and again only when FSEvents says it changed, so redrawing the
/// columns never touches the disk.
@MainActor
final class ColumnListings: ObservableObject {
    @Published private(set) var items: [URL: [FileItem]] = [:]
    private var wanted: [URL] = []
    private var hidden = false
    private var widths: [URL: (count: Int, width: CGFloat)] = [:]
    private var watcher: FolderWatcher?
    private var watchTask: Task<Void, Never>?

    /// Keeps the listings of these folders, reading new ones and dropping the rest.
    func track(_ folders: [URL], hidden: Bool) {
        if hidden != self.hidden {
            self.hidden = hidden
            items = [:]
        }
        wanted = folders
        for key in items.keys where !folders.contains(key) { items[key] = nil }
        for folder in folders where items[folder] == nil { load(folder) }
        watch(folders)
    }

    /// The column's width for its longest name (R7), measured once per listing.
    func width(of items: [FileItem], in folder: URL) -> CGFloat {
        if let known = widths[folder], known.count == items.count { return known.width }
        let width = Self.measure(items)
        widths[folder] = (items.count, width)
        return width
    }

    func stop() {
        watchTask?.cancel()
        watcher?.stop()
        watcher = nil
    }

    private func load(_ folder: URL) {
        let hidden = self.hidden
        Task { [weak self] in
            let listing = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let items = (try? FolderReader.items(in: folder, showHidden: hidden)) ?? []
                return ItemSorter.sorted(items, by: ItemSort())
            }.value
            guard let self, self.hidden == hidden, self.wanted.contains(folder) else { return }
            self.items[folder] = listing
        }
    }

    private func watch(_ folders: [URL]) {
        let paths = folders.map(\.path)
        if watcher?.paths == paths { return }
        stop()
        guard !paths.isEmpty else { return }
        let watcher = FolderWatcher(paths: paths, latency: 0.3)
        guard watcher.start() else { return }
        self.watcher = watcher
        let changes = watcher.changes
        watchTask = Task { [weak self] in
            for await batch in changes { self?.changed(batch) }
        }
    }

    private func changed(_ batch: [FolderChange]) {
        for folder in wanted {
            let real = FolderWatcher.realPath(folder.path)
            let touched = batch.contains { $0.path == real || ($0.recursive && FolderChange.isInside(real, $0.path)) }
            if touched { load(folder) }
        }
    }

    private static func measure(_ items: [FileItem]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let names = items.count > 2_000
            ? Array(items.map(\.name).sorted { $0.count > $1.count }.prefix(300))
            : items.map(\.name)
        return CGFloat(ColumnWidth.fitting(names) { Double(($0 as NSString).size(withAttributes: [.font: font]).width) })
    }
}
