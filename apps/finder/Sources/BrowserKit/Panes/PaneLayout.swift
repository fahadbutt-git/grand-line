import Foundation

/// One to four side-by-side panes (R12, R27). Tab moves the focus to the next
/// pane; F5 and F6 copy or move to it.
public struct PaneLayout: Codable, Equatable, Sendable {
    public static let range = 1...4
    public private(set) var count: Int
    public private(set) var focused: Int

    public init(count: Int = 1, focused: Int = 0) {
        self.count = min(Self.range.upperBound, max(Self.range.lowerBound, count))
        self.focused = min(self.count - 1, max(0, focused))
    }

    /// Columns and rows: 1, 2 and 3 panes sit side by side; 4 make a 2 by 2 grid.
    public var grid: (columns: Int, rows: Int) {
        count == 4 ? (2, 2) : (count, 1)
    }

    /// The pane F5 and F6 send to: the next one, wrapping. nil with one pane.
    public var nextPane: Int? {
        count > 1 ? (focused + 1) % count : nil
    }

    public mutating func setCount(_ n: Int) {
        self = PaneLayout(count: n, focused: focused)
    }

    /// Tab.
    public mutating func focusNext() {
        focused = (focused + 1) % count
    }

    /// Shift+Tab.
    public mutating func focusPrevious() {
        focused = (focused + count - 1) % count
    }

    public mutating func focus(_ index: Int) {
        focused = min(count - 1, max(0, index))
    }

    /// Opens a pane after the focused one and focuses it. Returns its index, or
    /// nil when four are open.
    @discardableResult
    public mutating func addPane() -> Int? {
        guard count < Self.range.upperBound else { return nil }
        count += 1
        focused += 1
        return focused
    }

    /// Closes a pane; the last one stays.
    @discardableResult
    public mutating func closePane(_ index: Int) -> Bool {
        guard count > 1, (0..<count).contains(index) else { return false }
        count -= 1
        if focused >= index, focused > 0 { focused -= 1 }
        focused = min(focused, count - 1)
        return true
    }
}

/// What F5 or F6 does between two panes.
public enum PaneTransfer: Equatable, Sendable {
    case copy(to: URL)
    case move(to: URL)
    /// From inside an archive both keys extract the selected items (R26).
    case extract(to: URL)

    public static func plan(moving: Bool, from source: BrowserLocation, to destination: BrowserLocation) -> PaneTransfer? {
        guard let folder = destination.folderURL else { return nil }
        if source.isArchive { return .extract(to: folder) }
        if let from = source.folderURL, from.standardizedFileURL == folder.standardizedFileURL, moving { return nil }
        return moving ? .move(to: folder) : .copy(to: folder)
    }
}
