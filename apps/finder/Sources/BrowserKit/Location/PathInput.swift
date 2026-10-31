import Foundation

/// The editable path bar and Go to Folder, both on Cmd+Shift+G (R5).
public enum PathInput {
    /// What typed text asks for: a path, or a folder name to find in the index.
    public enum Intent: Equatable, Sendable {
        case path(URL)
        case fuzzy(String)
    }

    /// Paths start with `/`, `~`, `.` or a short name such as `Drive/`, or contain
    /// a slash. Anything else is a folder name to look up.
    public static func interpret(_ text: String, relativeTo current: URL, home: URL, aliases: [String: URL] = [:]) -> Intent? {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return nil }
        guard looksLikePath(trimmed, aliases: aliases),
              let url = resolve(trimmed, relativeTo: current, home: home, aliases: aliases) else {
            return .fuzzy(trimmed)
        }
        return .path(url)
    }

    /// Whether typed text is a path rather than a name: it starts with `/`, `~`
    /// or `.`, holds a slash, is a file URL, or is a short name such as `Drive`.
    public static func looksLikePath(_ text: String, aliases: [String: URL] = [:]) -> Bool {
        let trimmed = clean(text)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.hasPrefix(".")
            || trimmed.contains("/") || trimmed.hasPrefix("file://") || aliases[trimmed] != nil
    }

    /// `~/x`, `/x`, `file:///x`, `Drive/x` (an alias), or a path relative to the
    /// current folder, with `..` resolved.
    public static func resolve(_ text: String, relativeTo current: URL, home: URL, aliases: [String: URL] = [:]) -> URL? {
        var path = clean(text)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL {
            return url.standardizedFileURL
        }
        if path == "~" {
            path = home.path
        } else if path.hasPrefix("~/") {
            path = home.path + String(path.dropFirst(1))
        } else if !path.hasPrefix("/") {
            let first = path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? path
            if let root = aliases[first] {
                let rest = String(path.dropFirst(first.count))
                path = root.path + rest
            } else {
                path = current.path + "/" + path
            }
        }
        let standard = (path as NSString).standardizingPath
        return URL(fileURLWithPath: standard.isEmpty ? "/" : standard, isDirectory: true)
    }

    /// What Go to Folder says under the field when Return finds nothing, so
    /// the field never just stays as it was.
    public static func notFound(_ intent: Intent, home: URL) -> String {
        switch intent {
        case .path(let url):
            return "No folder at \(PathSegments.editableText(for: url, home: home))"
        case .fuzzy(let name):
            return "No folder named \u{201C}\(name)\u{201D}"
        }
    }

    /// A folder name typed as is: a folder of that name in the current
    /// folder, else in the home folder, before the index is asked.
    public static func nearbyFolder(named name: String, in current: URL, home: URL,
                                    isFolder: (URL) -> Bool) -> URL? {
        guard !name.isEmpty, !name.contains("/") else { return nil }
        for parent in [current, home] {
            let candidate = parent.appendingPathComponent(name, isDirectory: true)
            if isFolder(candidate) { return candidate }
        }
        return nil
    }

    static func clean(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("'", "'"), ("\u{201C}", "\u{201D}")] where trimmed.count >= 2 {
            if trimmed.hasPrefix(open), trimmed.hasSuffix(close) {
                trimmed = String(trimmed.dropFirst().dropLast())
            }
        }
        // Paths pasted from a terminal keep their backslash escapes.
        trimmed = trimmed.replacingOccurrences(of: "\\ ", with: " ")
        if trimmed.count > 1, trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    /// What Tab makes of the text: the one matching folder in full (ending in
    /// a slash, ready for the next level); with several, as much as they share
    /// beyond what is typed, else the first. `options` are `completions`, and
    /// `editable` writes a folder as the field shows it (`~/Documents`).
    public static func complete(_ text: String, options: [URL], editable: (URL) -> String) -> String? {
        guard let first = options.first else { return nil }
        if options.count == 1 { return editable(first) + "/" }
        let typed = text.trimmingCharacters(in: .whitespaces)
        let stem = typed.hasSuffix("/") ? "" : (typed as NSString).lastPathComponent
        let names = options.map(\.lastPathComponent)
        let shared = commonPrefix(names)
        if shared.count > stem.count {
            let parent = editable(first.deletingLastPathComponent())
            return (parent.hasSuffix("/") ? parent : parent + "/") + shared
        }
        return editable(first) + "/"
    }

    /// The longest start all names share, ignoring case, spelled as in the first.
    static func commonPrefix(_ names: [String]) -> String {
        guard var shared = names.first.map({ Array($0) }) else { return "" }
        for name in names.dropFirst() {
            let other = Array(name)
            var length = 0
            while length < shared.count, length < other.count,
                  String(shared[length]).lowercased() == String(other[length]).lowercased() {
                length += 1
            }
            shared = Array(shared.prefix(length))
        }
        return String(shared)
    }

    /// Tab completion: folders in the typed parent whose names start with the
    /// typed last part, ignoring case. `children` lists a folder's subfolder names.
    public static func completions(
        for text: String, relativeTo current: URL, home: URL,
        aliases: [String: URL] = [:], children: (URL) -> [String]
    ) -> [URL] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let endsWithSlash = typed.hasSuffix("/")
        guard let resolved = resolve(typed.isEmpty ? "." : typed, relativeTo: current, home: home, aliases: aliases) else { return [] }
        let parent = endsWithSlash || typed.isEmpty ? resolved : resolved.deletingLastPathComponent()
        let stem = endsWithSlash || typed.isEmpty ? "" : resolved.lastPathComponent.lowercased()
        return children(parent)
            .filter { stem.isEmpty || $0.lowercased().hasPrefix(stem) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { parent.appendingPathComponent($0, isDirectory: true) }
    }
}
