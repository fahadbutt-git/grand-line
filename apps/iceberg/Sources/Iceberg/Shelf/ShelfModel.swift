import AppKit
import Combine
import IcebergKit

/// The files on the shelf, shared by the panel on every display and the
/// drop basket. It keeps a bookmark per file in `shelf.json` (IcebergKit's
/// `ShelfFile`), so the shelf is the same after a restart; the files stay
/// where they are. Taking one off the shelf, or clearing it, forgets the
/// bookmark only. Quick actions write new files beside the original.
@MainActor
final class ShelfModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let item: ShelfItem
        /// Where the file is now, nil when it cannot be found.
        let url: URL?
        let isDirectory: Bool
        var id: String { item.id }
        var missing: Bool { url == nil }
    }

    @Published private(set) var entries: [Entry] = []
    /// Items with a quick action running.
    @Published private(set) var working: Set<String> = []
    /// A file is being dragged over a panel that takes it.
    @Published var isDropTargeted = false
    /// The last quick action's result, shown for a few seconds.
    @Published private(set) var note: String?
    /// `shelf_quick_actions`.
    @Published var quickActionsEnabled = true

    private var list: ShelfList
    private let file: URL
    private var icons: [String: NSImage] = [:]
    private var noteWork: DispatchWorkItem?

    init(paths: IcebergPaths) {
        file = paths.shelfFile
        list = ShelfFile.load(from: file)
        resolve()
    }

    // MARK: The list

    /// Files dropped on the notch or the basket. Returns the ids now on
    /// the shelf for them (new or already there).
    @discardableResult
    func add(_ urls: [URL]) -> [String] {
        let items = urls.filter(\.isFileURL).compactMap { ShelfBookmark.item(for: $0) }
        guard !items.isEmpty else { return [] }
        list.add(items)
        save()
        resolve()
        let paths = Set(items.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        return list.items.filter { paths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path) }.map(\.id)
    }

    /// Off the shelf. The file is not touched.
    func remove(_ id: String) {
        list.remove(id: id)
        save()
        resolve()
    }

    /// Everything off the shelf. No file is touched.
    func clear() {
        list.removeAll()
        save()
        resolve()
    }

    /// The panel opened: files may have moved or gone since.
    func refresh() { resolve() }

    private func resolve() {
        var changed = false
        var next: [Entry] = []
        for item in list.items {
            guard let found = ShelfBookmark.resolve(item) else {
                next.append(Entry(item: item, url: nil, isDirectory: false))
                continue
            }
            var current = item
            if found.stale || found.url.path != item.path {
                // Moved or renamed: keep the new place, with a fresh bookmark.
                let fresh = ShelfBookmark.item(for: found.url)
                list.update(id: item.id, path: found.url.path, name: found.url.lastPathComponent, bookmark: fresh?.bookmark)
                current.path = found.url.path
                current.name = found.url.lastPathComponent
                changed = true
            }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: found.url.path, isDirectory: &isDir)
            next.append(Entry(item: current, url: found.url, isDirectory: isDir.boolValue))
        }
        if changed { save() }
        let live = Set(next.compactMap { $0.url?.path })
        icons = icons.filter { live.contains($0.key) }
        if next != entries { entries = next }
    }

    private func save() {
        do {
            try ShelfFile.save(list, to: file)
        } catch {
            Log.info("the shelf could not be saved: \(error.localizedDescription)")
        }
    }

    func icon(for entry: Entry) -> NSImage {
        guard let url = entry.url else {
            return NSImage(systemSymbolName: "questionmark.folder", accessibilityDescription: nil) ?? NSImage()
        }
        if let cached = icons[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        icons[url.path] = image
        return image
    }

    // MARK: Quick actions

    func actions(for entry: Entry) -> [QuickAction] {
        guard quickActionsEnabled, let url = entry.url else { return [] }
        return QuickAction.available(for: url, isDirectory: entry.isDirectory)
    }

    /// Runs one action. The result is a new file beside the original, which
    /// goes on the shelf too; the original is left as it is.
    func run(_ action: QuickAction, on entry: Entry) {
        guard quickActionsEnabled, let url = entry.url, !working.contains(entry.id) else { return }
        working.insert(entry.id)
        let id = entry.id
        let done: @Sendable (Result<URL, ToolError>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finished(id, action, result) }
            }
        }
        if action == .removeBackground {
            BackgroundRemover.run(source: url, completion: done)
            return
        }
        guard let plan = QuickActionPlan.invocation(action, source: url, isDirectory: entry.isDirectory,
                                                    exists: { FileManager.default.fileExists(atPath: $0.path) }) else {
            done(.failure(.noFreeName))
            return
        }
        ToolRunner.run(plan, completion: done)
    }

    private func finished(_ id: String, _ action: QuickAction, _ result: Result<URL, ToolError>) {
        working.remove(id)
        switch result {
        case .success(let out):
            add([out])
            show("Made \(out.lastPathComponent)")
        case .failure(let error):
            Log.info("\(action.title) failed: \(error)")
            show("\(action.title) did not work: \(error)")
        }
    }

    private func show(_ text: String) {
        note = text
        noteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.note = nil } }
        noteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: The menu of one file

    func menu(for entry: Entry) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if let url = entry.url {
            menu.addItem(ClosureMenuItem("Open", symbol: "arrow.up.forward.app") { NSWorkspace.shared.open(url) })
            menu.addItem(ClosureMenuItem("Show in Finder", symbol: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            })
            let actions = actions(for: entry)
            if !actions.isEmpty {
                menu.addItem(.separator())
                for action in actions {
                    let item = ClosureMenuItem(action.title, symbol: action.symbol) { [weak self] in self?.run(action, on: entry) }
                    item.isEnabled = !working.contains(entry.id)
                    menu.addItem(item)
                }
            }
        } else {
            let gone = NSMenuItem(title: "The file cannot be found", action: nil, keyEquivalent: "")
            gone.isEnabled = false
            menu.addItem(gone)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Remove from Shelf", symbol: "minus.circle") { [weak self] in self?.remove(entry.id) })
        return menu
    }

    func popUpMenu(for entry: Entry) {
        menu(for: entry).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
