import AppKit
import BrowserKit

/// Copy, real cut (R8) and paste, through the system pasteboard so files also
/// paste into other apps.
extension BrowserModel {
    func copy() {
        let urls = selectedOnDisk
        guard !urls.isEmpty else { return }
        FilePasteboard.write(urls, to: .general)
        services.clipboard.copy(urls)
    }

    func cut() {
        let urls = selectedOnDisk
        guard !urls.isEmpty else { return }
        FilePasteboard.write(urls, to: .general)
        services.clipboard.cut(urls, changeCount: NSPasteboard.general.changeCount)
    }

    func paste(forceMove: Bool) {
        guard let folder = focused.location.folderURL else { return }
        let board = NSPasteboard.general
        guard let plan = services.clipboard.plan(
            pasteboard: FilePasteboard.read(board), changeCount: board.changeCount, forceMove: forceMove
        ) else { return }
        services.clipboard.didPaste(plan)
        runOperation(plan.moves ? "The items could not be moved." : "The items could not be copied.") { operations in
            if plan.moves { return try await operations.move(plan.items, to: folder) }
            return try await operations.copy(plan.items, to: folder)
        }
    }

    func copyPath() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(CopyPath.text(for: focused.selectedItems), forType: .string)
    }
}

enum FilePasteboard {
    static func write(_ urls: [URL], to board: NSPasteboard) {
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
    }

    static func read(_ board: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (board.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}
