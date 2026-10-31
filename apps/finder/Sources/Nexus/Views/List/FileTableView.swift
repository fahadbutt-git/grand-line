import AppKit
import BrowserKit

/// The table: keys go to the coordinator first, right-click builds the
/// context menu, and the selection is offered to Services and Quick Actions.
final class FileTableView: NSTableView {
    weak var coordinator: FileListCoordinator?

    override func keyDown(with event: NSEvent) {
        if coordinator?.handle(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return coordinator?.menu(forRow: row)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        coordinator?.sourceMask(local: context == .withinApplication) ?? .copy
    }

    // MARK: Services

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == .fileURL, returnType == nil, coordinator?.pane.selectedItems.contains(where: { !$0.isInArchive }) == true {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let urls = coordinator?.pane.selectedItems.filter({ !$0.isInArchive }).map(\.url), !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls.map { $0 as NSURL })
    }
}

/// Selected rows in the theme's selection colour, not the system accent.
final class ThemedRowView: NSTableRowView {
    var selectionColor: NSColor = .selectedContentBackgroundColor

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        selectionColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
