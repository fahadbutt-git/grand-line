import CoreServices
import Foundation

/// Finder's Date Last Opened: Spotlight's kMDItemLastUsedDate. No URL resource
/// key carries it, so it is read per item, and only while a pane sorts by it.
public enum LastOpened {
    public static func date(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Dates by path; never-opened items get `distantPast`, so they sort last
    /// and are not looked up again.
    public static func dates(for urls: [URL]) -> [String: Date] {
        var result: [String: Date] = [:]
        for url in urls { result[url.path] = date(of: url) ?? .distantPast }
        return result
    }
}
