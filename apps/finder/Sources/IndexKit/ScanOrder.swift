import Foundation

/// Which folders a first build walks first and last, so the places people search
/// most can be searched within moments of a first launch.
public struct ScanOrder: Sendable, Equatable {
    /// Walked before everything else, in this order.
    public var first: [String]
    /// Walked after everything else, in this order.
    public var last: [String]

    public init(first: [String] = [], last: [String] = []) {
        self.first = first
        self.last = last
    }

    public static let none = ScanOrder()

    /// ~/Downloads, ~/Desktop and ~/Documents first, then the rest of the home
    /// folder, then Google Drive and other cloud folders in ~/Library/CloudStorage.
    public static func home(_ home: String) -> ScanOrder {
        let base = FolderWatcher.realPath(home)
        return ScanOrder(
            first: ["Downloads", "Desktop", "Documents"].map { IndexStorage.join(base, $0) },
            last: [IndexStorage.join(base, "Library/CloudStorage")]
        )
    }
}
