import AppKit
import BrowserKit
import SwiftUI

/// The list view: an NSTableView, for speed with 100,000 rows, drag and drop,
/// in-place rename and the Services menu.
struct FileListView: NSViewRepresentable {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    @ObservedObject var services: Services
    @ObservedObject var theme: ThemeStore
    let isFocused: Bool

    init(model: BrowserModel, pane: PaneModel, palette: Palette, isFocused: Bool) {
        self.model = model
        self.pane = pane
        self.services = model.services
        self.theme = model.services.theme
        self.isFocused = isFocused
    }

    func makeCoordinator() -> FileListCoordinator {
        FileListCoordinator(model: model, pane: pane)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = FileTableView()
        table.coordinator = context.coordinator
        context.coordinator.table = table
        FileTableSetup.configure(table, coordinator: context.coordinator)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.pane = pane
        let colors = theme.theme
        scroll.backgroundColor = NSColor(colors.background)
        coordinator.table?.backgroundColor = NSColor(colors.background)
        coordinator.update(theme: colors, cut: services.clipboard.cutPaths, renameRequest: model.renameRequest)
        // Not while Go to Folder is open: its field is about to take the keys.
        // Checked again once this update is over: when Return closes the path
        // bar's field, this runs while its editor still has the keys, and the
        // field going away left them with the window, so the list never got
        // them back (and Escape never reached it to clear a filter).
        if isFocused, !model.editingPath, let table = coordinator.table, model.window?.firstResponder !== table {
            let model = self.model
            DispatchQueue.main.async { [weak table] in
                guard let table, let window = table.window, !model.editingPath, window.firstResponder !== table,
                      !Self.isTyping(in: window) else { return }
                window.makeFirstResponder(table)
            }
        }
    }

    /// A field on screen is being typed in. A field editor left behind by a
    /// field that has gone (no longer in the window) does not count.
    static func isTyping(in window: NSWindow) -> Bool {
        guard let text = window.firstResponder as? NSText else { return false }
        return text.window === window && text.superview != nil
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: FileListCoordinator) {
        coordinator.table = nil
    }
}

/// Columns and table behaviour, set once.
@MainActor
enum FileTableSetup {
    static let rowHeight: CGFloat = 24

    static func configure(_ table: FileTableView, coordinator: FileListCoordinator) {
        table.headerView = NSTableHeaderView()
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 6, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .noColumnAutoresizing
        for column in ListColumn.standard.map(FileColumn.init) { table.addTableColumn(makeColumn(column)) }
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(FileListCoordinator.doubleClicked(_:))
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
    }

    static func makeColumn(_ column: FileColumn) -> NSTableColumn {
        let tableColumn = NSTableColumn(identifier: column.identifier)
        tableColumn.title = column.title
        tableColumn.width = column.width
        tableColumn.minWidth = 60
        tableColumn.headerCell.alignment = column.alignment
        return tableColumn
    }

    /// Shows exactly `columns`, in their order: a saved search's own set, or
    /// Where added in flat view. Columns already shown keep their width.
    static func apply(_ columns: [FileColumn], to table: NSTableView) {
        let wanted = columns.map(\.identifier)
        guard table.tableColumns.map(\.identifier) != wanted else { return }
        for column in table.tableColumns where !wanted.contains(column.identifier) { table.removeTableColumn(column) }
        for (index, column) in columns.enumerated() {
            if table.tableColumn(withIdentifier: column.identifier) == nil { table.addTableColumn(makeColumn(column)) }
            let current = table.column(withIdentifier: column.identifier)
            if current >= 0, current != index { table.moveColumn(current, toColumn: index) }
        }
    }
}

/// A list column on screen, from BrowserKit's `ListColumn`.
enum FileColumn: String, CaseIterable {
    case name, path, modified, created, added, size, kind

    init(_ column: ListColumn) {
        self = FileColumn(rawValue: column.rawValue) ?? .name
    }

    var list: ListColumn { ListColumn(rawValue: rawValue) ?? .name }

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String { list.title }

    var width: CGFloat {
        switch self {
        case .name: return 320
        case .path: return 220
        case .modified, .created, .added: return 150
        case .size: return 80
        case .kind: return 140
        }
    }

    var alignment: NSTextAlignment { self == .size ? .right : .left }

    var sortField: SortField { list.sortField }
}
