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
        if isFocused, let table = coordinator.table, model.window?.firstResponder !== table,
           !(model.window?.firstResponder is NSText) {
            DispatchQueue.main.async { table.window?.makeFirstResponder(table) }
        }
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
        for column in FileColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = 60
            tableColumn.headerCell.alignment = column.alignment
            table.addTableColumn(tableColumn)
        }
        table.dataSource = coordinator
        table.delegate = coordinator
        table.target = coordinator
        table.doubleAction = #selector(FileListCoordinator.doubleClicked(_:))
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .link, .generic], forLocal: false)
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.draggingDestinationFeedbackStyle = .regular
    }
}

enum FileColumn: String, CaseIterable {
    case name, modified, size, kind

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .name: return "Name"
        case .modified: return "Date Modified"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }

    var width: CGFloat {
        switch self {
        case .name: return 320
        case .modified: return 150
        case .size: return 80
        case .kind: return 140
        }
    }

    var alignment: NSTextAlignment { self == .size ? .right : .left }

    var sortField: SortField {
        switch self {
        case .name: return .name
        case .modified: return .modified
        case .size: return .size
        case .kind: return .kind
        }
    }
}
