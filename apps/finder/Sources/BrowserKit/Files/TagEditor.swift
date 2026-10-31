import Foundation

/// Finder tags (R10, R21). Ctrl+1 to Ctrl+7 toggle the colour tags as Finder
/// does: if every selected item has the tag it comes off, otherwise all get it.
public enum TagEditor {
    public static let colors = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

    public static func color(for command: BrowserCommand) -> String? {
        let order: [BrowserCommand] = [.tagRed, .tagOrange, .tagYellow, .tagGreen, .tagBlue, .tagPurple, .tagGray]
        return order.firstIndex(of: command).map { colors[$0] }
    }

    /// Each item's tags after toggling `tag` across all of them.
    public static func toggling(_ tag: String, in tagLists: [[String]]) -> [[String]] {
        let everyHas = !tagLists.isEmpty && tagLists.allSatisfy { $0.contains(tag) }
        return tagLists.map { tags in
            everyHas ? tags.filter { $0 != tag } : (tags.contains(tag) ? tags : tags + [tag])
        }
    }

    /// The inspector's editor: the common tags were edited from `old` to `new`;
    /// each item keeps its other tags.
    public static func applying(common old: [String], edited new: [String], to tags: [String]) -> [String] {
        let removed = Set(old).subtracting(new)
        var result = tags.filter { !removed.contains($0) }
        for tag in new where !result.contains(tag) { result.append(tag) }
        return result
    }

    /// "urgent, review" typed in a field.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    public static func read(_ url: URL) -> [String] {
        (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    public static func write(_ tags: [String], to url: URL) throws {
        try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
    }
}
