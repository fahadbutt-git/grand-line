import AppKit
import ArchiveKit
import BrowserKit
import FileKit
import ThemeKit
import UniformTypeIdentifiers

/// Feeds the table from the pane and sends clicks, edits and drops back.
@MainActor
final class FileListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var model: BrowserModel
    var pane: PaneModel
    weak var table: FileTableView?
    private var shownIDs: [String] = []
    private var shownCut: Set<String> = []
    private var theme: Theme?
    private var renameRequest = 0
    private var syncing = false
    private var typeSelect = TypeSelect()

    init(model: BrowserModel, pane: PaneModel) {
        self.model = model
        self.pane = pane
    }

    var items: [FileItem] { pane.items }

    // MARK: Updates from the model

    func update(theme: Theme, cut: Set<String>, renameRequest request: Int) {
        guard let table else { return }
        let ids = pane.state.ids
        let themeChanged = self.theme != theme
        self.theme = theme
        if ids != shownIDs || cut != shownCut || themeChanged {
            let scrollToTop = shownIDs.isEmpty || ids.first != shownIDs.first && ids.count != shownIDs.count
            shownIDs = ids
            shownCut = cut
            table.reloadData()
            fitNameColumn()
            if scrollToTop { table.scrollRowToVisible(0) }
        }
        syncSelection()
        if request != renameRequest {
            renameRequest = request
            beginRename()
        }
    }

    private func syncSelection() {
        guard let table else { return }
        var wanted = IndexSet()
        for (row, id) in shownIDs.enumerated() where pane.state.selection.contains(id) { wanted.insert(row) }
        guard wanted != table.selectedRowIndexes else { return }
        syncing = true
        table.selectRowIndexes(wanted, byExtendingSelection: false)
        if let first = wanted.first { table.scrollRowToVisible(first) }
        syncing = false
    }

    /// The name column fits the longest name (R7); long lists measure the
    /// longest few hundred names by length.
    private func fitNameColumn() {
        guard let column = table?.tableColumn(withIdentifier: FileColumn.name.identifier) else { return }
        let names = items.count > 2_000
            ? items.map(\.name).sorted { $0.count > $1.count }.prefix(300).map { $0 }
            : items.map(\.name)
        let font = NSFont.systemFont(ofSize: 13)
        column.width = ColumnWidth.fitting(names) { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
    }

    func beginRename() {
        guard let table, table.selectedRowIndexes.count == 1, let row = table.selectedRowIndexes.first,
              row < items.count, !items[row].isInArchive else { return }
        table.editColumn(0, row: row, with: nil, select: true)
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < items.count, let column = FileColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let item = items[row]
        let cell = (tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? FileCellView)
            ?? FileCellView(column: column, identifier: tableColumn.identifier)
        cell.textField?.delegate = self
        cell.show(item, column: column, row: FileCellView.Info(
            folderSize: pane.state.folderSizes[item.path],
            badge: pane.badges[item.id],
            isCut: shownCut.contains(item.url.standardizedFileURL.path),
            theme: theme
        ))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = ThemedRowView()
        if let theme { view.selectionColor = NSColor(theme.selection) }
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let table else { return }
        let ids = table.selectedRowIndexes.compactMap { $0 < shownIDs.count ? shownIDs[$0] : nil }
        pane.select(ids: ids)
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let column = FileColumn(rawValue: tableColumn.identifier.rawValue) else { return }
        model.sort(pane, by: column.sortField)
    }

    @objc func doubleClicked(_ sender: Any?) {
        guard let table, table.clickedRow >= 0 else { return }
        model.open(pane.selectedItems, in: pane)
    }

    // MARK: Rename

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let table else { return }
        let row = table.row(for: field)
        guard row >= 0, row < items.count else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == items[row].name {
            field.stringValue = items[row].name
        } else {
            model.rename(items[row], to: name)
        }
        table.window?.makeFirstResponder(table)
    }

    // MARK: Keys

    /// Handles the keys the list owns (R4): Return, F2, Space, Tab, F5, F6,
    /// Cmd+Up and Cmd+Delete. Letters select by name. Returns false for the rest.
    func handle(_ event: NSEvent) -> Bool {
        let shortcut = Shortcut.from(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                                     modifiers: Self.modifiers(event.modifierFlags))
        guard let shortcut else { return false }
        let context = model.context
        if let command = KeyMap.command(for: shortcut, inArchive: context.inArchive, inTrash: context.inTrash) {
            switch shortcut.key {
            case .up, .down, .left, .right:
                if shortcut.modifiers.isEmpty || shortcut.modifiers == [.shift] { return false }
            default: break
            }
            if model.isEnabled(command) { model.perform(command) } else { NSSound.beep() }
            return true
        }
        if shortcut.modifiers.isEmpty, case .character(let text) = shortcut.key, let index = typeSelect.type(text, names: items.map(\.name)) {
            pane.select(ids: [items[index].id])
            return true
        }
        return false
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> Shortcut.Modifiers {
        var result: Shortcut.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    func menu(forRow row: Int) -> NSMenu {
        if row >= 0, row < shownIDs.count, !pane.state.selection.contains(shownIDs[row]) {
            pane.select(ids: [shownIDs[row]])
        } else if row < 0 {
            pane.select(ids: [])
        }
        model.focus(pane)
        return SelectionMenu.make(for: model)
    }

    // MARK: Drag out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        let item = items[row]
        if let entry = item.archiveEntry, case .archive(let archive, _) = pane.location {
            let type = item.isFolder ? UTType.folder : (UTType(filenameExtension: item.ext) ?? .data)
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: ArchivePromise.shared)
            provider.userInfo = ArchivePromise.Entry(archive: archive, entry: entry, name: item.name)
            return provider
        }
        return item.url as NSURL
    }

    /// Dragging out of Google Drive copies (R14).
    func sourceMask(local: Bool) -> NSDragOperation {
        let urls = pane.selectedItems.filter { !$0.isInArchive }.map(\.url)
        let drives = GoogleDrive.accounts(home: model.services.paths.home)
        if !local, urls.contains(where: { url in drives.contains { $0.contains(url) } }) { return .copy }
        return local ? [.move, .copy] : [.copy, .move, .link, .generic]
    }

    // MARK: Drop in

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard pane.location.folderURL != nil else { return [] }
        if operation == .on, row < items.count, !items[row].isFolder {
            tableView.setDropRow(row, dropOperation: .above)
        }
        if (info.draggingSource as AnyObject?) === tableView, operation == .above { return .move }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .generic
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let folder = pane.location.folderURL else { return false }
        let urls = FilePasteboard.read(info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        if (info.draggingSource as AnyObject?) === tableView, dropOperation == .above {
            pane.moveManually(urls.map(\.lastPathComponent), to: row)
            return true
        }
        let target = dropOperation == .on && row < items.count && items[row].isFolder ? items[row].url : folder
        model.drop(urls, into: target, forceCopy: NSEvent.modifierFlags.contains(.option))
        return true
    }
}

/// Extracts an archive entry where a drag out of an archive pane lands (R26).
/// AppKit calls it on its own operation queue, so nothing here is main-actor bound.
final class ArchivePromise: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    static let shared = ArchivePromise()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    final class Entry: NSObject {
        let archive: URL
        let entry: String
        let name: String

        init(archive: URL, entry: String, name: String) {
            self.archive = archive
            self.entry = entry
            self.name = name
        }
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        (filePromiseProvider.userInfo as? Entry)?.name ?? "Item"
    }

    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping (Error?) -> Void) {
        guard let entry = filePromiseProvider.userInfo as? Entry else {
            completionHandler(CocoaError(.fileNoSuchFile))
            return
        }
        do {
            _ = try Archive.extract([entry.entry], from: entry.archive, to: url.deletingLastPathComponent())
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    nonisolated func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        queue
    }
}
