import AppKit
import ArchiveKit
import BrowserKit
import Quartz

/// Space for Quick Look (R13), also for items inside archives, which are
/// extracted to a temporary folder first (R26).
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var urls: [URL] = []

    func toggle(for model: BrowserModel) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            panelClosed()
            return
        }
        prepare(model.focused) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.urls = urls
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    /// Option+Cmd+Y: the selection fills the screen, as in Finder.
    func showFullScreen(for model: BrowserModel) {
        guard let panel = QLPreviewPanel.shared() else { return }
        prepare(model.focused) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.urls = urls
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
            if !panel.isInFullScreenMode { _ = panel.enterFullScreenMode(nil, withOptions: nil) }
        }
    }

    /// Follows the selection while the panel is open.
    func selectionChanged(_ pane: PaneModel) {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        prepare(pane) { [weak self] urls in
            self?.urls = urls
            panel.reloadData()
        }
    }

    /// The panel is gone: its copies of archive items are removed from
    /// $TMPDIR/Archive Preview (security note L2). Items opened in apps and
    /// the preview pane's item live in folders of their own.
    func panelClosed() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true { return }
        urls = []
        // Only what is there now: a preview made a moment later for a panel
        // opened again is left alone.
        let doomed = (try? FileManager.default.contentsOfDirectory(
            at: Archive.TemporaryFolder.quickLook, includingPropertiesForKeys: nil)) ?? []
        guard !doomed.isEmpty else { return }
        Task.detached(priority: .utility) {
            for folder in doomed { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private func prepare(_ pane: PaneModel, done: @escaping ([URL]) -> Void) {
        let items = pane.selectedItems
        guard case .archive(let archive, _) = pane.location else {
            done(items.map(\.url))
            return
        }
        let entries = ArchiveRows.entries(items.filter { !$0.isFolder })
        Task {
            let urls = await Task.detached { entries.compactMap { try? Archive.preview($0, from: archive) } }.value
            done(urls)
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }

    /// Arrow keys in the panel go back to the list, as in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        return MainActor.assumeIsolated {
            guard let window = NSApp.mainWindow else { return false }
            window.sendEvent(event)
            return true
        }
    }
}
