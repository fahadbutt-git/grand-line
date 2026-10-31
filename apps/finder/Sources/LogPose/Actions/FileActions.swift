import AppKit
import BrowserKit
import FileKit

/// New folder, duplicate, rename, alias, compress, Trash and Put Back, tags,
/// undo and redo, Add to Sidebar. Everything goes through FileKit, so each step can be undone (R8, R21).
extension BrowserModel {
    var selectedOnDisk: [URL] { focused.selectedItems.filter { !$0.isInArchive }.map(\.url) }

    /// Runs file work in order, then refreshes the Undo title and selects the result.
    func runOperation(_ title: String, _ body: @escaping (FileOperations) async throws -> [URL]) {
        let operations = services.operations
        let pane = focused
        Task { [weak self] in
            do {
                let made = try await body(operations)
                self?.services.refreshUndo()
                if !made.isEmpty, let folder = pane.location.folderURL {
                    pane.go(.folder(folder), select: made)
                }
            } catch {
                self?.services.refreshUndo()
                Prompt.problem(title, error)
            }
        }
    }

    func newFolder(withSelection: Bool) {
        guard let folder = focused.location.folderURL else { return }
        let items = withSelection ? selectedOnDisk : []
        runOperation("The folder could not be made.") { operations in
            let made = try await operations.newFolder(in: folder, named: withSelection ? "New Folder With Items" : "untitled folder")
            if !items.isEmpty { _ = try await operations.move(items, to: made) }
            return [made]
        }
        renameAfterLoad()
    }

    /// The new folder is selected once the pane reloads; then its name is edited.
    private func renameAfterLoad() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.renameRequest += 1
        }
    }

    func duplicate() {
        let items = selectedOnDisk
        runOperation("The items could not be duplicated.") { try await $0.duplicate(items) }
    }

    func rename(_ item: FileItem, to name: String) {
        guard name != item.name, !item.isInArchive else { return }
        runOperation("The item could not be renamed.") { operations in
            let renamed = try await operations.rename(item.url, to: name)
            return [renamed]
        }
    }

    func makeAlias() {
        do {
            let made = try selectedOnDisk.map { try AliasFile.make(for: $0) }
            if let folder = focused.location.folderURL { focused.go(.folder(folder), select: made) }
        } catch {
            Prompt.problem("The alias could not be made.", error)
        }
    }

    func showOriginal() {
        guard let item = selectedOnDisk.first, let original = AliasFile.original(of: item) else {
            Prompt.problem("The original item could not be found.")
            return
        }
        focused.go(.folder(original.deletingLastPathComponent()), select: [original])
    }

    func compress() {
        guard let plan = CompressPlan.make(for: selectedOnDisk) else { return }
        let pane = focused
        Task {
            do {
                let result = try await ProcessRunner.run(plan.command)
                if !result.succeeded { Prompt.problem("Compressing failed. " + result.errorText) }
                if let folder = pane.location.folderURL { pane.go(.folder(folder), select: [plan.destination]) }
            } catch {
                Prompt.problem("Compressing failed.", error)
            }
        }
    }

    func moveToTrash() {
        let items = selectedOnDisk
        guard !items.isEmpty else { return }
        let services = self.services
        runOperation("The items could not be moved to the Trash.") { operations in
            let trashed = try await operations.moveToTrash(items)
            await MainActor.run { services.noteTrashed(items, to: trashed) }
            return []
        }
    }

    /// Put Back: each item returns to its folder under its old name.
    func putBack() {
        let items = selectedOnDisk
        let ledger = services.trashLedger
        let services = self.services
        runOperation("The items could not be put back.") { operations in
            for item in items {
                guard let place = ledger.destination(of: item) else { continue }
                let moved = try await operations.move([item], to: place.folder)
                if let back = moved.first, back.lastPathComponent != place.name,
                   !FileManager.default.fileExists(atPath: place.folder.appendingPathComponent(place.name).path) {
                    _ = try await operations.rename(back, to: place.name)
                }
                await MainActor.run { services.notePutBack(item) }
            }
            return []
        }
    }

    /// Emptying is Finder's own action, asked of Finder, after you confirm unless
    /// you held Option (Opt+Shift+Cmd+Delete, as in Finder). Log Pose itself
    /// never deletes a file.
    func emptyTrash(asking: Bool) {
        if asking, !Prompt.confirm(
            "Empty the Trash?", message: "Items in the Trash are removed for good. This cannot be undone.", action: "Empty Trash"
        ) { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if error != nil { Prompt.problem("The Trash could not be emptied.") }
        focused.reload()
    }

    func undo() {
        let operations = services.operations
        let pane = focused
        Task { [weak self] in
            do {
                _ = try await operations.undo()
            } catch {
                Prompt.problem("Undo failed.", error)
            }
            self?.services.refreshUndo()
            pane.reload()
        }
    }

    func redo() {
        let operations = services.operations
        let pane = focused
        Task { [weak self] in
            do {
                _ = try await operations.redo()
            } catch {
                Prompt.problem("Redo failed.", error)
            }
            self?.services.refreshUndo()
            pane.reload()
        }
    }

    // MARK: Sidebar

    /// The selected folder, or the pane's folder with nothing selected.
    var sidebarCandidate: URL? {
        let folders = focused.selectedItems.filter { $0.isFolder && !$0.isInArchive }
        if focused.selectedItems.isEmpty { return focused.location.folderURL }
        return folders.count == 1 ? folders[0].url : nil
    }

    func addToSidebar() {
        guard let folder = sidebarCandidate else { return }
        services.addPlace(folder)
    }

    // MARK: Tags

    func toggleTag(_ command: BrowserCommand) {
        guard let tag = TagEditor.color(for: command) else { return }
        let urls = selectedOnDisk
        let updated = TagEditor.toggling(tag, in: urls.map(TagEditor.read))
        writeTags(updated, to: urls)
    }

    func removeTags() {
        let urls = selectedOnDisk
        writeTags(urls.map { _ in [] }, to: urls)
    }

    func setCommonTags(from old: [String], to new: [String]) {
        let urls = selectedOnDisk
        writeTags(urls.map { TagEditor.applying(common: old, edited: new, to: TagEditor.read($0)) }, to: urls)
    }

    func writeTags(_ lists: [[String]], to urls: [URL]) {
        do {
            for (url, tags) in zip(urls, lists) { try TagEditor.write(tags, to: url) }
        } catch {
            Prompt.problem("The tags could not be changed.", error)
        }
        focused.reload()
    }

    // MARK: Clutter

    /// R11: .DS_Store and ._ files go to the Trash in one undoable step.
    func cleanClutter() {
        guard let folder = focused.location.folderURL else { return }
        let found = Clutter.find(in: folder)
        guard !found.isEmpty else {
            Prompt.problem("No .DS_Store or ._ files were found here.")
            return
        }
        guard Prompt.confirm(
            "Move \(ItemFormat.count(found.count, "clutter file")) to the Trash?",
            message: "These are .DS_Store and ._ files that macOS leaves on drives and shares. Undo puts them back.",
            action: "Move to Trash"
        ) else { return }
        runOperation("The files could not be moved to the Trash.") { operations in
            _ = try await Clutter.clean(in: folder, using: operations)
            return []
        }
    }
}
