import Foundation

/// One clickable part of the path bar: "Drive › 01 Research › _Active".
public struct PathSegment: Hashable, Sendable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public enum PathSegments {
    /// Starts at the deepest short name that holds the folder (such as "Drive"
    /// for a Google Drive's My Drive), then "~" for home, then the disk root.
    public static func segments(for folder: URL, home: URL, aliases: [String: URL] = [:], rootTitle: String = "/") -> [PathSegment] {
        let path = folder.standardizedFileURL.path
        var bases: [(title: String, path: String)] = aliases.map { (title: $0.key, path: $0.value.standardizedFileURL.path) }
        bases.append(("~", home.standardizedFileURL.path))
        let match = bases
            .filter { path == $0.path || path.hasPrefix($0.path + "/") }
            .max { $0.path.count < $1.path.count }
        let (title, base) = match.map { ($0.title, $0.path) } ?? (rootTitle, "/")
        var result = [PathSegment(title: title, url: URL(fileURLWithPath: base, isDirectory: true))]
        let rest = String(path.dropFirst(base.count)).split(separator: "/").map(String.init)
        var current = base
        for part in rest {
            current = current == "/" ? "/" + part : current + "/" + part
            result.append(PathSegment(title: part, url: URL(fileURLWithPath: current, isDirectory: true)))
        }
        return result
    }

    /// The text the path bar shows when you start editing: `~/Downloads`.
    public static func editableText(for folder: URL, home: URL) -> String {
        let path = folder.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }
}
