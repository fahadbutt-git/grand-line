import AppKit
import BrowserKit
import FileKit

/// New folder, duplicate, rename, alias, compress, Trash and Put Back, tags,
/// undo and redo, Add to Sidebar. Everything goes through FileKit as a task
/// (`Services.tasks`), so each step shows in the tasks popover, can be
/// cancelled, and can be undone (R8, R21).
extension BrowserModel {
    var selectedOnDisk: [URL] { focused.selectedItems.filter { !$0.isInArchive }.map(\.url) }

    /// Runs file work as a task after the others, then selects what it made.
    /// A cancelled task says nothing; a failed one says why.
    func runOperation(_ kind: FileOperationKind?, _ title: String, failure: String,
                      _ body: @escaping @Sendable (FileOperations) async throws -> [URL]) {
        let services = self.services
        let pane = focused
        Task {
            do {
                let made = try await services.run(kind, title, body)
                if !made.isEmpty, let folder = pane.location.folderURL {
                    pane.go(.folder(folder), select: made)
                }
            } catch is CancellationError {
                pane.reload()
            } catch {
                Prompt.problem(failure, error)
            }
            services.refreshUndo()
        }
    }

    func newFolder(withSelection: Bool) {
        guard let folder = focused.location.folderURL else { return }
        let items = withSelection ? selectedOnDisk : []
        runOperation(.newFolder, "New folder in \(folder.lastPathComponent)", failure: "The folder could not be made.") { operations in
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
        runOperation(.duplicate, TaskTitles.title(.duplicate, items), failure: "The items could not be duplicated.") {
            try await $0.duplicate(items)
        }
    }

    /// F2 or File › Rename: one item is renamed in place; several open Rename
    /// N Items, as in Finder.
    func beginRename() {
        let items = selectedOnDisk
        if items.count > 1 {
            batchRenameItems = items
        } else {
            renameRequest += 1
        }
    }

    func rename(_ item: FileItem, to name: String) {
        guard name != item.name, !item.isInArchive else { return }
        let oldExtension = (item.name as NSString).pathExtension
        let newExtension = (name as NSString).pathExtension
        if !item.isFolder, oldExtension.lowercased() != newExtension.lowercased(),
           NexusPreferencesStore.shared.current.warnBeforeChangingExtension,
           !Prompt.confirm(
               newExtension.isEmpty ? "Remove the extension \".\(oldExtension)\"?" : "Change the extension to \".\(newExtension)\"?",
               message: "The file may open in a different app.",
               action: newExtension.isEmpty ? "Remove" : "Use .\(newExtension)"
           ) { return }
        let url = item.url
        runOperation(.rename, "Rename \(item.name)", failure: "The item could not be renamed.") { operations in
            [try await operations.rename(url, to: name)]
        }
    }

    /// Rename N Items: every name at once, undone at once.
    func renameItems(_ rows: [BatchRename.Row]) {
        let pairs = rows.filter(\.changes).map { (item: $0.item, name: $0.new) }
        guard !pairs.isEmpty else { return }
        runOperation(.renameItems, "Rename \(ItemFormat.count(pairs.count))", failure: "The items could not be renamed.") { operations in
            try await operations.renameItems(pairs)
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

    /// Compress runs as a task; Undo moves the archive to the Trash.
    func compress() {
        let items = selectedOnDisk
        guard let plan = CompressPlan.make(for: items) else { return }
        runOperation(.compress, TaskTitles.title(.compress, items), failure: "Compressing failed.") { operations in
            try Task.checkCancellation()
            let result = try await ProcessRunner.run(plan.command)
            guard result.succeeded else { throw TaskProblem(result.errorText) }
            await operations.recordCreated([plan.destination], kind: .compress)
            return [plan.destination]
        }
    }

    func moveToTrash() {
        let items = selectedOnDisk
        guard !items.isEmpty else { return }
        let services = self.services
        runOperation(.trash, TaskTitles.title(.trash, items), failure: "The items could not be moved to the Trash.") { operations in
            let trashed = try await operations.moveToTrash(items)
            await MainActor.run { services.noteTrashed(Array(items.prefix(trashed.count)), to: trashed) }
            return []
        }
    }

    /// Put Back: each item returns to its folder under its old name, in one
    /// step that Undo reverses.
    func putBack() {
        let items = selectedOnDisk
        let ledger = services.trashLedger
        let services = self.services
        let entries = items.compactMap { item -> (item: URL, original: URL)? in
            guard let place = ledger.destination(of: item) else { return nil }
            return (item: item, original: place.folder.appendingPathComponent(place.name))
        }
        guard !entries.isEmpty else { return }
        runOperation(.putBack, TaskTitles.title(.putBack, entries.map { $0.item }), failure: "The items could not be put back.") { operations in
            let back = try await operations.putBack(entries)
            await MainActor.run { for entry in entries { services.notePutBack(entry.item) } }
            return back
        }
    }

    /// Emptying is Finder's own action, asked of Finder, after you confirm unless
    /// you held Option (Opt+Shift+Cmd+Delete, as in Finder). Nexus itself
    /// never deletes a file.
    func emptyTrash(asking: Bool) {
        if asking, NexusPreferencesStore.shared.current.warnBeforeEmptyingTrash, !Prompt.confirm(
            "Empty the Trash?", message: "Items in the Trash are removed for good. This cannot be undone.", action: "Empty Trash"
        ) { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        if error != nil { Prompt.problem("The Trash could not be emptied.") }
        focused.reload()
    }

    /// Undo and Redo wait their turn behind running tasks, so they never
    /// reverse something half done.
    func undo(steps: Int = 1) {
        let services = self.services
        let pane = focused
        let title = steps == 1 ? (services.undoTitle ?? "Undo") : "Undo \(steps) steps"
        Task {
            do {
                _ = try await services.run(nil, title) { operations in
                    _ = try await operations.undo(steps: steps)
                    return []
                }
            } catch is CancellationError {
            } catch {
                Prompt.problem("Undo failed.", error)
            }
            services.refreshUndo()
            pane.reload()
        }
    }

    func redo() {
        let services = self.services
        let pane = focused
        Task {
            do {
                _ = try await services.run(nil, services.redoTitle ?? "Redo") { operations in
                    _ = try await operations.redo()
                    return []
                }
            } catch is CancellationError {
            } catch {
                Prompt.problem("Redo failed.", error)
            }
            services.refreshUndo()
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

    /// A favourite tag's chip in the inspector, as Ctrl+1 to 7 toggle the colours.
    func toggleTag(named tag: String) {
        let urls = selectedOnDisk
        writeTags(TagEditor.toggling(tag, in: urls.map(TagEditor.read)), to: urls)
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
        runOperation(.trash, "Move \(ItemFormat.count(found.count, "clutter file")) to the Trash",
                     failure: "The files could not be moved to the Trash.") { operations in
            _ = try await Clutter.clean(in: folder, using: operations)
            return []
        }
    }
}
