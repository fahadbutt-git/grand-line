import AppKit

/// Files on a real pasteboard: written as file URLs, so they also paste into
/// Finder and other apps, and read back as file URLs only.
public enum SystemPasteboard {
    public static func write(_ urls: [URL], to board: NSPasteboard) {
        board.clearContents()
        board.writeObjects(urls.map { $0 as NSURL })
    }

    public static func read(_ board: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = board.readObjects(forClasses: [NSURL.self], options: options) ?? []
        return objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
    }

    /// `ClipboardFlow`'s view of `board`.
    public static func access(_ board: NSPasteboard) -> PasteboardAccess {
        PasteboardAccess(
            changeCount: { board.changeCount },
            write: { write($0, to: board) },
            read: { read(board) }
        )
    }
}
