import AppKit
import BrowserKit

/// Copy, real cut (R8) and paste, through the system pasteboard so files also
/// paste into other apps. The steps are BrowserKit's `ClipboardFlow`, the same
/// path the tests drive, and each one leaves a line in nexus.log.
extension BrowserModel {
    func copy() {
        let pasteboard = SystemPasteboard.access(.general)
        if !ClipboardFlow.copy(ClipboardFlow.items(in: focused.state), clipboard: &services.clipboard, pasteboard: pasteboard) {
            NSSound.beep()
        }
    }

    func cut() {
        let pasteboard = SystemPasteboard.access(.general)
        if !ClipboardFlow.copy(ClipboardFlow.items(in: focused.state), cut: true, clipboard: &services.clipboard, pasteboard: pasteboard) {
            NSSound.beep()
        }
    }

    func paste(forceMove: Bool) {
        let pane = focused
        let folder = pane.location.folderURL
        guard let plan = ClipboardFlow.paste(into: folder, clipboard: &services.clipboard,
                                             pasteboard: SystemPasteboard.access(.general), forceMove: forceMove),
              let folder else {
            NSSound.beep()
            return
        }
        transfer(plan.items, to: folder, moving: plan.moves, select: pane)
    }

    func copyPath() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(CopyPath.text(for: focused.selectedItems), forType: .string)
    }
}

/// Files on a pasteboard (drops read the dragging pasteboard this way).
enum FilePasteboard {
    static func write(_ urls: [URL], to board: NSPasteboard) {
        SystemPasteboard.write(urls, to: board)
    }

    static func read(_ board: NSPasteboard) -> [URL] {
        SystemPasteboard.read(board)
    }
}
