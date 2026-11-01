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
    /// The rows as last drawn. The table reads these, not the pane's live
    /// items, so a row number always means the item drawn there, even while
    /// a reload is held back for a name being edited.
    private var shown: [FileItem] = []
    private var shownCut: Set<String> = []
    /// A reload that waited for a name being edited to end.
    private var heldReload = false
    private var theme: Theme?
    /// Kind colours, extensions and row height from Settings, as last drawn.
    private var display: FileCellView.Display?
    private var renameRequest = 0
    private var syncing = false
    /// The place the rows were last drawn for: leaving it ends a rename.
    private var shownLocation: BrowserLocation?
    /// Set while a rename is dropped because the pane went somewhere else.
    private var discarding = false
    /// When the pane last went somewhere else, and whether a rename was asked
    /// for (F2, a new folder): `FileTableView` lets a name be edited then.
    private var placeChanged = Date.distantPast
    private(set) var renaming = false

    /// The pane has just gone somewhere else: a click that AppKit still takes
    /// as a click to edit a name belongs to the place that has gone.
    var justChangedPlace: Bool {
        Date().timeIntervalSince(placeChanged) < NSEvent.doubleClickInterval + 0.3
    }
    private var typeSelect = TypeSelect()

    init(model: BrowserModel, pane: PaneModel) {
        self.model = model
        self.pane = pane
    }

    var items: [FileItem] { shown }

    // MARK: Updates from the model

    func update(theme: Theme, cut: Set<String>, renameRequest request: Int, isFocused: Bool = true) {
        guard let table else { return }
        let ids = pane.state.ids
        let themeChanged = self.theme != theme
        self.theme = theme
        let store = NexusPreferencesStore.shared
        let display = FileCellView.Display(kindColours: store.current.showKindColours,
                                           allExtensions: store.current.showAllExtensions,
                                           rowHeight: store.rowHeight(theme: theme))
        let displayChanged = display != self.display
        self.display = display
        if table.rowHeight != display.rowHeight { table.rowHeight = display.rowHeight }
        let columns = ListColumn.shown(pane.state.settings.columns, flat: pane.state.isFlat).map(FileColumn.init)
        let columnsChanged = table.tableColumns.map(\.identifier) != columns.map(\.identifier)
        if columnsChanged { FileTableSetup.apply(columns, to: table) }
        // A name being edited when the pane goes somewhere else (a double-click
        // that opened the folder, Back, Go to Folder) is dropped: its row is
        // about to show another item, and the editor would otherwise keep the
        // keys, so Cmd+C and Cmd+V went to it instead of the files.
        if let shown = shownLocation, shown != pane.location {
            placeChanged = Date()
            discardRename()
        }
        shownLocation = pane.location
        if ids != shownIDs || cut != shownCut || themeChanged || displayChanged || columnsChanged || heldReload {
            if editingField() != nil {
                // A name is being edited (a download finished, a file changed
                // nearby): reloading now would end the edit or move the row
                // under it. The rows stay as they are until the edit ends.
                heldReload = true
            } else {
                reloadRows(ids: ids, cut: cut)
            }
        }
        if !heldReload { syncSelection() }
        if request != renameRequest {
            renameRequest = request
            // Only the focused list renames, and only the item it was asked for.
            if isFocused { beginRename(target: model.renameTarget) }
        }
    }

    private func reloadRows(ids: [String], cut: Set<String>) {
        guard let table else { return }
        heldReload = false
        let scrollToTop = shownIDs.isEmpty || ids.first != shownIDs.first && ids.count != shownIDs.count
        shownIDs = ids
        shown = pane.items
        shownCut = cut
        table.reloadData()
        fitNameColumn()
        if scrollToTop { table.scrollRowToVisible(0) }
        visibleRowsChanged()
    }

    /// The held reload, once the edit has ended.
    private func reloadIfHeld() {
        guard heldReload, editingField() == nil else { return }
        reloadRows(ids: pane.state.ids, cut: model.services.clipboard.cutPaths)
        syncSelection()
    }

    /// The name field being edited in this table, if any.
    private func editingField() -> NSTextField? {
        guard let table, let window = table.window, let editor = window.firstResponder as? NSText,
              let field = editor.delegate as? NSTextField, field.isDescendant(of: table) else { return nil }
        return field
    }

    /// Scrolling or resizing: the pane measures the folders now on screen.
    @objc func visibleRowsChanged(_ notification: Notification? = nil) {
        guard let table else { return }
        let range = table.rows(in: table.visibleRect)
        guard range.length > 0 else { return }
        let lower = max(0, range.location)
        let upper = min(shown.count, range.location + range.length)
        guard lower < upper else { return }
        pane.setVisible(shown[lower..<upper].map(\.id))
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
        let all = display?.allExtensions ?? true
        let names = items.count > 2_000
            ? items.map { $0.shownName(allExtensions: all) }.sorted { $0.count > $1.count }.prefix(300).map { $0 }
            : items.map { $0.shownName(allExtensions: all) }
        let font = NSFont.systemFont(ofSize: 13)
        column.width = ColumnWidth.fitting(names) { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
    }

    /// Ends a rename without renaming, and gives the keys back to the list.
    private func discardRename() {
        guard let table, let window = table.window, let editor = window.firstResponder as? NSText,
              let field = editor.delegate as? NSTextField, field.isDescendant(of: table) else { return }
        discarding = true
        _ = field.abortEditing()
        discarding = false
        window.makeFirstResponder(table)
        NexusLog.note("list: a rename in progress was dropped because the pane changed place")
    }

    func beginRename(target: String? = nil) {
        guard let table, table.selectedRowIndexes.count == 1, let row = table.selectedRowIndexes.first,
              row < items.count, !items[row].isInArchive else { return }
        if let target, items[row].id != target { return }
        renaming = true
        table.editColumn(0, row: row, with: nil, select: true)
        renaming = false
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
            theme: theme,
            display: display ?? FileCellView.Display(),
            place: column == .path ? place(of: item) : ""
        ))
        return cell
    }

    /// Where an item is: below the flat view's folder, else its own folder.
    private func place(of item: FileItem) -> String {
        if pane.state.isFlat, let folder = pane.location.folderURL {
            return FlatListing.relativeFolder(of: item.path, under: folder.path)
        }
        return PathSegments.editableText(for: item.url.deletingLastPathComponent(), home: model.services.paths.home)
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
        defer { DispatchQueue.main.async { [weak self] in self?.reloadIfHeld() } }
        let row = table.row(for: field)
        // The item the field was showing when editing began: rows are not
        // reloaded while a name is edited, and the cell says which item it is.
        var cell: NSView? = field.superview
        while let view = cell, !(view is FileCellView) { cell = view.superview }
        let id = (cell as? FileCellView)?.itemID ?? (row >= 0 && row < items.count ? items[row].id : nil)
        let item = id.flatMap { id in pane.items.first { $0.id == id } ?? items.first { $0.id == id } }
        guard !discarding, row >= 0, let item else {
            // The row has gone (reloaded away): nothing to rename, but the keys
            // must not stay with an editor that is no longer on screen.
            DispatchQueue.main.async { [weak table] in
                guard let table, let window = table.window, !TextFieldGuard.isTyping(in: window) else { return }
                window.makeFirstResponder(table)
            }
            return
        }
        let allExtensions = NexusPreferencesStore.shared.current.showAllExtensions
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = item.shownName(allExtensions: allExtensions)
        if typed.isEmpty || typed == shown || typed == item.name {
            field.stringValue = shown
        } else {
            model.rename(item, to: item.typedName(typed, allExtensions: allExtensions))
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
        // Escape clears the omnibar's filter, as it does in the field.
        if shortcut == Shortcut(.escape), !pane.state.filter.isEmpty {
            model.clearFilter(in: pane)
            return true
        }
        let context = model.context
        // Tab and Shift+Tab move between panes only where there are panes to
        // move between; otherwise they select the next or previous item by
        // name, as in Finder.
        if shortcut.key == .tab, shortcut.modifiers.isEmpty || shortcut.modifiers == [.shift],
           !model.isEnabled(shortcut.modifiers.isEmpty ? .nextPane : .previousPane) {
            let names = items.map { (id: $0.id, name: $0.name) }
            if let id = TabSelect.target(items: names, selected: Set(pane.selectedItems.map(\.id)), backwards: shortcut.modifiers == [.shift]) {
                pane.select(ids: [id])
            }
            return true
        }
        if let found = KeyMap.command(for: shortcut, inArchive: context.inArchive, inTrash: context.inTrash) {
            let command = NexusPreferencesStore.shared.current.returnKey.command(found, for: shortcut)
            switch shortcut.key {
            case .up, .down, .left, .right:
                if shortcut.modifiers.isEmpty || shortcut.modifiers == [.shift] { return false }
            default: break
            }
            let enabled = model.isEnabled(command)
            if BrowserWindowController.traced.contains(command) {
                NexusLog.note("list key \(shortcut): \(command.rawValue)\(enabled ? "" : " is not available here")")
            }
            if enabled { model.perform(command) } else { NSSound.beep() }
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
        // A file promise (Mail, Photos, Safari, an archive pane) is always a copy.
        if FilePasteboard.read(info.draggingPasteboard).isEmpty, Self.promises(in: info.draggingPasteboard) != nil { return .copy }
        if (info.draggingSource as AnyObject?) === tableView, operation == .above { return .move }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .generic
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let folder = pane.location.folderURL else { return false }
        let urls = FilePasteboard.read(info.draggingPasteboard)
        guard !urls.isEmpty else {
            guard let promises = Self.promises(in: info.draggingPasteboard) else { return false }
            let target = dropOperation == .on && row < items.count && items[row].isFolder ? items[row].url : folder
            model.receive(promises, into: target)
            return true
        }
        if (info.draggingSource as AnyObject?) === tableView, dropOperation == .above {
            pane.moveManually(urls.map(\.lastPathComponent), to: row)
            return true
        }
        let target = dropOperation == .on && row < items.count && items[row].isFolder ? items[row].url : folder
        model.drop(urls, into: target, forceCopy: NSEvent.modifierFlags.contains(.option))
        return true
    }
}

extension FileListCoordinator {
    /// The file promises on a drag's pasteboard, nil when there are none.
    static func promises(in pasteboard: NSPasteboard) -> [NSFilePromiseReceiver]? {
        let found = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]
        return found?.isEmpty == false ? found : nil
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
