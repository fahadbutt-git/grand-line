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
            let items = selectedOnDisk
            runTransfer(into: target, "The items could not be copied.") { try await $0.copy(items, to: folder) }
        case .move(let folder)?:
            let items = selectedOnDisk
            runTransfer(into: target, "The items could not be moved.") { try await $0.move(items, to: folder) }
        case .extract(let folder)?:
            extract(to: folder)
        case nil:
            break
        }
    }

    /// The copies show selected in the pane they went to; the source reloads by itself.
    private func runTransfer(into target: PaneModel, _ title: String, _ body: @escaping (FileOperations) async throws -> [URL]) {
        let operations = services.operations
        Task { [weak self] in
            do {
                let made = try await body(operations)
                if let folder = target.location.folderURL { target.go(.folder(folder), select: made) }
            } catch {
                Prompt.problem(title, error)
            }
            self?.services.refreshUndo()
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
