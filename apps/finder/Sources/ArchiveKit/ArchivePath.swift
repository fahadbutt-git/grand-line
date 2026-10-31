import Foundation

/// Entry paths inside an archive. Paths that could land outside the destination
/// (an absolute path or a ".." part) are unsafe and never extracted.
public enum ArchivePath {
    /// "./a//b/" becomes "a/b".
    public static func normalize(_ path: String) -> String {
        var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        while parts.first == "." { parts.removeFirst() }
        parts.removeAll { $0 == "." }
        return parts.joined(separator: "/")
    }

    public static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.hasPrefix("\\") || path.contains("\0") { return false }
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        if parts.contains(where: { $0 == ".." }) { return false }
        if let first = parts.first, first.count == 2, first.last == ":" { return false }
        return !normalize(path).isEmpty
    }

    /// Escapes the characters bsdtar reads as a pattern, so a name matches only itself.
    static func pattern(_ path: String) -> String {
        var escaped = ""
        for c in path {
            if c == "*" || c == "?" || c == "[" || c == "\\" { escaped.append("\\") }
            escaped.append(c)
        }
        return escaped
    }

    /// Finder metadata a Mac adds when it zips: hidden like it is in folders.
    static func isMacMetadata(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard let last = parts.last else { return false }
        return parts.first == "__MACOSX" || last.hasPrefix("._") || last == ".DS_Store"
    }
}
