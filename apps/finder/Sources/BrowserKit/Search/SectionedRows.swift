import Foundation

/// The list's rows when search results show the "Found inside files" header
/// (`PaneState.insideFilesStart`): one more row than items, the header before
/// the first file found only by what is inside it. Maps table rows to items
/// and back, so selection, rename, drag and the context menu never take the
/// header for an item.
public struct SectionedRows: Equatable, Sendable {
    public let itemCount: Int
    /// The header's row, which is also the index of the first item after it.
    public let headerRow: Int?

    public init(itemCount: Int, headerBefore: Int?) {
        self.itemCount = max(0, itemCount)
        if let headerBefore, headerBefore >= 0, headerBefore < itemCount {
            headerRow = headerBefore
        } else {
            headerRow = nil
        }
    }

    public var rowCount: Int { itemCount + (headerRow == nil ? 0 : 1) }

    public func isHeader(_ row: Int) -> Bool { row == headerRow }

    /// The item drawn at `row`; nil for the header and rows past the end.
    public func item(atRow row: Int) -> Int? {
        guard row >= 0, row < rowCount, row != headerRow else { return nil }
        if let headerRow, row > headerRow { return row - 1 }
        return row
    }

    /// The row `item` is drawn at.
    public func row(ofItem item: Int) -> Int {
        if let headerRow, item >= headerRow { return item + 1 }
        return item
    }

    /// The items drawn in rows `range` (the header left out).
    public func items(inRows range: Range<Int>) -> Range<Int> {
        let indices = range.compactMap { item(atRow: $0) }
        guard let first = indices.first, let last = indices.last else { return 0..<0 }
        return first..<(last + 1)
    }
}
