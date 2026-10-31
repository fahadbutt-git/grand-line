import Foundation

/// The pasteboard as Cmd+C and Cmd+V use it: Nexus passes the system's
/// general pasteboard (`SystemPasteboard.access`), the tests one of their own.
public struct PasteboardAccess {
    public var changeCount: () -> Int
    /// Replaces what is on the pasteboard with these files.
    public var write: ([URL]) -> Void
    /// File URLs on the pasteboard, as they come.
    public var read: () -> [URL]

    public init(changeCount: @escaping () -> Int, write: @escaping ([URL]) -> Void, read: @escaping () -> [URL]) {
        self.changeCount = changeCount
        self.write = write
        self.read = read
    }
}

/// Cmd+C, Cmd+X and Cmd+V from a pane, one path for Nexus's windows and the
/// tests: what is selected goes on the pasteboard and into `FileClipboard`;
/// a paste then becomes a plan for `TransferFlow` into the pane's folder.
/// Every step says what it did in `NexusLog`, so a paste that made nothing
/// can be traced afterwards.
public enum ClipboardFlow {
    /// The items Cmd+C takes from a pane: its selection, without archive entries.
    public static func items(in pane: PaneState) -> [URL] {
        pane.selectedItems.filter { !$0.isInArchive }.map(\.url)
    }

    /// Puts `items` on the pasteboard and remembers them as copied (or cut).
    /// False, and nothing changes, when there is nothing to copy.
    @discardableResult
    public static func copy(_ items: [URL], cut: Bool = false, clipboard: inout FileClipboard, pasteboard: PasteboardAccess) -> Bool {
        let verb = cut ? "cut" : "copy"
        guard !items.isEmpty else {
            NexusLog.note("\(verb): nothing selected, the pasteboard is left as it was")
            return false
        }
        pasteboard.write(items)
        let count = pasteboard.changeCount()
        if cut {
            clipboard.cut(items, changeCount: count)
        } else {
            clipboard.copy(items, changeCount: count)
        }
        NexusLog.note("\(verb) \(NexusLog.names(items)) (pasteboard change \(count))")
        return true
    }

    /// Cmd+V (or Option+Cmd+V, `forceMove`) into `folder`: what to copy or
    /// move there, or nil (and why, in the log) when there is nothing to paste
    /// or the pane shows no folder. A cut is used up by the paste.
    public static func paste(into folder: URL?, clipboard: inout FileClipboard, pasteboard: PasteboardAccess,
                             forceMove: Bool = false) -> FileClipboard.PastePlan? {
        guard let folder else {
            NexusLog.note("paste: this pane shows no folder (a search, Recents or an archive)")
            return nil
        }
        let count = pasteboard.changeCount()
        var readBack: Int?
        let plan = clipboard.plan(reading: {
            let urls = pasteboard.read()
            readBack = urls.count
            return urls
        }, changeCount: count, forceMove: forceMove)
        let source: String
        if let readBack {
            let own: String = clipboard.ownChangeCount.map { "\($0)" } ?? "none"
            source = "read \(readBack) URL(s) from the pasteboard (change \(count); Nexus's own was \(own))"
        } else {
            source = "Nexus's own \(clipboard.mode == .cut ? "cut" : "copy"), still on the pasteboard (change \(count))"
        }
        guard let plan else {
            NexusLog.note("paste into \(folder.path): nothing to paste; \(source)")
            return nil
        }
        clipboard.didPaste(plan)
        NexusLog.note("paste into \(folder.path): \(plan.moves ? "move" : "copy") \(NexusLog.names(plan.items)); \(source)")
        return plan
    }
}
