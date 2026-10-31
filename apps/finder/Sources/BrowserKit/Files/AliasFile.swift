import FileKit
import Foundation

/// Finder aliases: bookmark files that follow the original when it moves.
public enum AliasFile {
    /// "Report.pdf alias", or "Report.pdf alias 2" when taken.
    public static func name(for item: URL, in folder: URL) -> String {
        FileNaming.available(item.lastPathComponent + " alias", in: folder)
    }

    /// Makes an alias beside the item and returns it.
    @discardableResult
    public static func make(for item: URL, in folder: URL? = nil) throws -> URL {
        let place = folder ?? item.deletingLastPathComponent()
        let alias = place.appendingPathComponent(name(for: item, in: place))
        let data = try item.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: alias)
        return alias
    }

    /// Show Original (Cmd+R) and opening an alias: where it points, or nil when
    /// the item is not an alias or the original is gone.
    public static func original(of item: URL) -> URL? {
        let values = try? item.resourceValues(forKeys: [.isAliasFileKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return item.resolvingSymlinksInPath() }
        guard values?.isAliasFile == true else { return nil }
        return try? URL(resolvingAliasFileAt: item, options: [.withoutUI])
    }
}
