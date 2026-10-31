import AppKit
import BrowserKit
import FileKit

/// Tab between panes, F5 and F6 to the next pane (R27), pinning and workspaces (R12).
extension BrowserModel {
    func nextPane(forward: Bool) {
        guard mode == .panes, layout.count > 1 else { return }
        if forward { layout.focusNext() } else { layout.focusPrevious() }
        selectionChanged()
    }

    func transferToNextPane(moving: Bool) {
        guard let next = layout.nextPane, next < panes.count else { return }
        let target = panes[next]
        switch PaneTransfer.plan(moving: moving, from: focused.location, to: target.location) {
        case .copy(let folder)?:
            transfer(selectedOnDisk, to: folder, moving: false, select: target)
        case .move(let folder)?:
            transfer(selectedOnDisk, to: folder, moving: true, select: target)
        case .extract(let folder)?:
            extract(to: folder)
        case nil:
            break
        }
    }

    func togglePin() {
        pinned.toggle()
        window?.level = pinned ? .floating : .normal
        window?.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    func saveWorkspace() {
        guard let name = Prompt.text(
            "Save Workspace", message: "The panes, their folders and this window's view.",
            value: focused.location.title, action: "Save"
        ) else { return }
        do {
            try services.workspaces.save(snapshot(named: name))
        } catch {
            Prompt.problem("The workspace could not be saved.", error)
        }
    }
}
