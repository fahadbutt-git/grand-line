import Foundation

/// A browser bookmark, from Zen (ZenBookmarks).
public struct Bookmark: Sendable, Equatable {
    public let title: String
    public let url: String
    /// "Bookmarks toolbar › Research".
    public let folder: String

    public init(title: String, url: String, folder: String) {
        self.title = title
        self.url = url
        self.folder = folder
    }
}

/// The `%` provider: Zen's bookmarks as results.
public enum Bookmarks {
    public static func host(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func results(_ bookmarks: [Bookmark]) -> [LaunchResult] {
        bookmarks.map { bookmark in
            LaunchResult(
                id: "bm:" + bookmark.url,
                title: bookmark.title,
                subtitle: bookmark.folder,
                icon: .symbol("bookmark"),
                section: .bookmarks,
                keywords: [host(bookmark.url), bookmark.folder],
                accessory: host(bookmark.url),
                actions: [
                    LaunchAction("Open", symbol: "globe", .openURL(bookmark.url, bundleID: nil)),
                    .copy(bookmark.url, title: "Copy URL"),
                    .favourite,
                ],
                providerID: "bookmarks"
            )
        }
    }

    public static func provider(paths: GrandLinePaths = GrandLinePaths()) -> CatalogProvider {
        CatalogProvider(id: "bookmarks", title: "Bookmarks", symbol: "bookmark", prefix: .bookmarks, globalLimit: 12) {
            results(ZenBookmarks.load(profilesFolder: paths.zen))
        }
    }
}
