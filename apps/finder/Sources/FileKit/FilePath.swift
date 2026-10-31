import Foundation

/// One spelling for each location, whether or not the item still exists.
/// URL's standardizedFileURL drops macOS's "/private" only while the item is
/// there, so a path saved before a delete would no longer match after it.
public enum FilePath {
    private static let privateRoots = ["/private/var", "/private/tmp", "/private/etc"]

    /// "." and ".." resolved by text, and /private/var, /private/tmp and
    /// /private/etc shown as /var, /tmp and /etc, as Finder shows them.
    public static func canonical(_ url: URL) -> URL {
        var path = URL(fileURLWithPath: url.path).standardized.path
        for root in privateRoots where path == root || path.hasPrefix(root + "/") {
            path.removeFirst("/private".count)
            break
        }
        return URL(fileURLWithPath: path)
    }
}
