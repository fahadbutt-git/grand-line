import AppKit
import ArchiveKit
import BrowserKit
import FileKit
import UniformTypeIdentifiers

/// Opening (R4), Open With (R34) and items inside archives (R26).
extension BrowserModel {
    func openSelection() {
        open(focused.selectedItems, in: focused)
    }

    func open(_ chosen: [FileItem], in pane: PaneModel) {
        let resolved = chosen.map(resolveAlias)
        let action = pane.state.openAction(for: resolved)
        if let target = action.navigate { pane.go(target) }
        for folder in action.windows { WindowManager.shared.newWindow(at: folder) }
        if !action.launch.isEmpty {
            for url in action.launch { NSWorkspace.shared.open(url) }
            services.noteOpened(action.launch)
        }
        if !action.fromArchive.isEmpty { openFromArchive(action.fromArchive, in: pane, app: nil) }
    }

    /// An alias opens what it points to.
    private func resolveAlias(_ item: FileItem) -> FileItem {
        guard item.isAlias, let original = AliasFile.original(of: item.url), let target = FileItem.read(original) else { return item }
        return target
    }

    func openWith(_ app: URL) {
        let pane = focused
        let inArchive = pane.selectedItems.filter(\.isInArchive)
        if !inArchive.isEmpty { openFromArchive(inArchive, in: pane, app: app) }
        let urls = selectedOnDisk
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { DispatchQueue.main.async { Prompt.problem("The items could not be opened.", error) } }
        }
        services.noteOpened(urls)
    }

    func openWithOther() {
        let panel = NSOpenPanel()
        panel.message = "Choose an app to open the selection with"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let app = panel.url else { return }
        openWith(app)
    }

    /// The Open With choices for the selection: the table's apps first, then macOS's.
    func openWithChoices() -> [OpenWithApp] {
        let items = focused.selectedItems.filter { !$0.isFolder }
        guard let first = items.first else { return [] }
        let probe = first.isInArchive ? URL(fileURLWithPath: "/tmp/probe").appendingPathExtension(first.ext) : first.url
        let system = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        return OpenWithMenu.choices(
            forExtension: OpenWithMenu.sharedExtension(items) ?? first.ext,
            table: services.defaultApps, folders: OpenWithMenu.appFolders(home: services.paths.home), system: system
        )
    }

    /// Items in an archive are extracted to a temporary folder, then opened.
    func openFromArchive(_ items: [FileItem], in pane: PaneModel, app: URL?) {
        guard case .archive(let archive, _) = pane.location else { return }
        let entries = ArchiveRows.entries(items)
        Task {
            let result = await Task.detached { () -> Result<[URL], Error> in
                Result { try entries.map { try Archive.preview($0, from: archive, in: Archive.TemporaryFolder.opened) } }
            }.value
            switch result {
            case .success(let urls):
                if let app {
                    NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                } else {
                    for url in urls { NSWorkspace.shared.open(url) }
                }
            case .failure(let error):
                Prompt.problem("The item could not be taken out of the archive.", error)
            }
        }
    }

    // MARK: Extract

    /// Cmd+E in an archive: the selection goes to the next pane's folder, or
    /// beside the archive with one pane (R26). It runs as a task; the items
    /// keep the archive's quarantine flag and Undo moves them to the Trash.
    func extract(to destination: URL?) {
        guard case .archive(let archive, _) = focused.location else { return }
        let target = destination ?? nextPaneFolder() ?? archive.deletingLastPathComponent()
        let entries = ArchiveRows.entries(focused.selectedItems)
        guard !entries.isEmpty else { return }
        let panes = self.panes
        let services = self.services
        let names = entries.map { URL(fileURLWithPath: "/" + $0) }
        Task {
            do {
                let made = try await services.run(.extract, TaskTitles.title(.extract, names, to: target)) { operations in
                    try Task.checkCancellation()
                    let extracted = try await Task.detached(priority: .userInitiated) {
                        try Archive.extract(entries, from: archive, to: target)
                    }.value
                    await operations.recordCreated(extracted, kind: .extract)
                    return extracted
                }
                for pane in panes where pane.location.folderURL?.standardizedFileURL == target.standardizedFileURL {
                    pane.go(.folder(target), select: made)
                }
            } catch is CancellationError {
            } catch {
                Prompt.problem("The items could not be extracted.", error)
            }
            services.refreshUndo()
        }
    }

    func extractTo() {
        guard let folder = Prompt.folder("Extract the selected items to", start: nextPaneFolder()) else { return }
        extract(to: folder)
    }

    func nextPaneFolder() -> URL? {
        guard mode == .panes, let next = layout.nextPane, next < panes.count else { return nil }
        return panes[next].location.folderURL
    }
}
