import Foundation

/// Chrome's bookmarks, from each profile's Bookmarks JSON file. The `%`
/// provider lists Zen's first (ZenBookmarks), then Chrome's.
public struct Bookmark: Sendable, Equatable {
    public let title: String
    public let url: String
    /// "Bookmarks bar › Research".
    public let folder: String
}

public enum ChromeBookmarks {
    public static func parse(_ data: Data) -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        var found: [Bookmark] = []
        for key in ["bookmark_bar", "other", "synced"] {
            guard let root = roots[key] as? [String: Any] else { continue }
            walk(root, trail: [], into: &found)
        }
        return found
    }

    static func walk(_ node: [String: Any], trail: [String], into found: inout [Bookmark]) {
        let name = node["name"] as? String ?? ""
        switch node["type"] as? String {
        case "url":
            guard let url = node["url"] as? String else { return }
            found.append(Bookmark(title: name.isEmpty ? url : name, url: url, folder: trail.joined(separator: " › ")))
        case "folder":
            let here = trail + [name]
            for child in node["children"] as? [[String: Any]] ?? [] { walk(child, trail: here, into: &found) }
        default:
            break
        }
    }

    /// The Default profile and every "Profile N" folder. A URL found twice is listed once.
    public static func load(chromeFolder: String, fileManager: FileManager = .default) -> [Bookmark] {
        let profiles = ((try? fileManager.contentsOfDirectory(atPath: chromeFolder)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { ($0 == "Default" ? 0 : 1, $0) < ($1 == "Default" ? 0 : 1, $1) }
        var seen = Set<String>()
        var all: [Bookmark] = []
        for profile in profiles {
            guard let data = fileManager.contents(atPath: chromeFolder + "/" + profile + "/Bookmarks") else { continue }
            for bookmark in parse(data) where seen.insert(bookmark.url).inserted { all.append(bookmark) }
        }
        return all
    }

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
                    LaunchAction("Open in Chrome", symbol: "globe", .openURL(bookmark.url, bundleID: "com.google.Chrome")),
                    .copy(bookmark.url, title: "Copy URL"),
                    .favourite,
                ],
                providerID: "bookmarks"
            )
        }
    }

    public static func provider(paths: GrandLinePaths = GrandLinePaths()) -> CatalogProvider {
        CatalogProvider(id: "bookmarks", title: "Bookmarks", symbol: "bookmark", prefix: .bookmarks, globalLimit: 12) {
            var seen = Set<String>()
            let all = ZenBookmarks.load(profilesFolder: paths.zen) + load(chromeFolder: paths.chrome)
            return results(all.filter { seen.insert($0.url).inserted })
        }
    }
}
