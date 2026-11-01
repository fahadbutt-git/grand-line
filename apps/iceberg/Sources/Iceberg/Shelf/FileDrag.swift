import AppKit
import SwiftUI

/// Reading the files out of a drag.
enum FileDragPasteboard {
    static let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    static func hasFiles(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }
}

/// The source of every file dragged out of Iceberg. It offers a copy (or
/// an alias), never a move, so dropping a shelved file in Finder leaves
/// the original where it is.
final class ShelfDragSource: NSObject, NSDraggingSource {
    static let shared = ShelfDragSource()

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .link]
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
}

/// A file's row, made draggable: drag it to any app (a copy), double-click
/// to open it, right-click for its menu. Clicks are its own; it sits over
/// the icon and name only, so buttons beside it keep working.
final class DragOutView: NSView {
    var url: URL?
    var icon: NSImage?
    var onDoubleClick: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private var downEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func mouseUp(with event: NSEvent) { downEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent, let url else { return }
        let start = convert(down.locationInWindow, from: nil)
        let now = convert(event.locationInWindow, from: nil)
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        downEvent = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let side: CGFloat = 32
        let frame = NSRect(x: start.x - side / 2, y: start.y - side / 2, width: side, height: side)
        item.setDraggingFrame(frame, contents: icon ?? NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: down, source: ShelfDragSource.shared)
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// `DragOutView` in SwiftUI.
struct DragOutArea: NSViewRepresentable {
    let url: URL?
    let icon: NSImage?
    let onDoubleClick: () -> Void
    let menu: () -> NSMenu?

    func makeNSView(context: Context) -> DragOutView {
        let view = DragOutView()
        update(view)
        return view
    }

    func updateNSView(_ view: DragOutView, context: Context) { update(view) }

    private func update(_ view: DragOutView) {
        view.url = url
        view.icon = icon
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
    }
}

/// Takes files dropped on it (the open panel, the basket). It answers
/// "copy", never "move", so the app the files come from keeps them. Files
/// dragged out of Iceberg itself are not taken back.
@MainActor
final class FileDropTarget {
    var onDrop: (([URL]) -> Void)?
    var onHover: ((Bool) -> Void)?

    func entered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard onDrop != nil, !(info.draggingSource is ShelfDragSource),
              FileDragPasteboard.hasFiles(info.draggingPasteboard) else { return [] }
        onHover?(true)
        return .copy
    }

    func exited() { onHover?(false) }

    func perform(_ info: NSDraggingInfo) -> Bool {
        onHover?(false)
        guard let onDrop, !(info.draggingSource is ShelfDragSource) else { return false }
        let urls = FileDragPasteboard.fileURLs(info.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}
