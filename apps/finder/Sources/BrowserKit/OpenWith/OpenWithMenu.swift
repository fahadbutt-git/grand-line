import Foundation

/// One app in the Open With menu.
public struct OpenWithApp: Hashable, Sendable {
    public let name: String
    public let url: URL
    /// From default-apps.tsv; listed first.
    public let isPreferred: Bool
}

public enum OpenWithMenu {
    public static func appFolders(home: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Finds "<name>.app" in the app folders.
    public static func locate(_ name: String, in folders: [URL]) -> URL? {
        let file = name.hasSuffix(".app") ? name : name + ".app"
        for folder in folders {
            let url = folder.appendingPathComponent(file, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The table's installed apps for these files' extension first, then the apps
    /// macOS offers (`system`, from NSWorkspace), without repeats.
    public static func choices(
        forExtension ext: String, table: DefaultAppsTable, folders: [URL], system: [URL]
    ) -> [OpenWithApp] {
        var seen = Set<String>()
        var result: [OpenWithApp] = []
        for name in table.apps(for: ext) {
            guard let url = locate(name, in: folders), seen.insert(url.standardizedFileURL.path).inserted else { continue }
            result.append(OpenWithApp(name: name, url: url, isPreferred: true))
        }
        for url in system where seen.insert(url.standardizedFileURL.path).inserted {
            result.append(OpenWithApp(name: url.deletingPathExtension().lastPathComponent, url: url, isPreferred: false))
        }
        return result
    }

    /// The extension the menu is built for: the shared one, or nil when the
    /// selected files differ (then only apps for all of them would fit, so the
    /// menu shows the system's list for the first file).
    public static func sharedExtension(_ items: [FileItem]) -> String? {
        let exts = Set(items.map(\.ext))
        return exts.count == 1 ? exts.first : nil
    }
}
