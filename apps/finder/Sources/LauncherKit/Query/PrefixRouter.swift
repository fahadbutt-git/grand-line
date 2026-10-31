import Foundation

/// Reads the first character of a query: a prefix sends it to one provider, a
/// path goes to the path provider, anything else searches everything.
public struct PrefixRouter: Sendable {
    let pathExists: @Sendable (String) -> Bool

    public init(pathExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.pathExists = pathExists
    }

    public func parse(_ text: String) -> LaunchQuery {
        let raw = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return LaunchQuery(raw: raw) }
        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let second = trimmed.dropFirst().first

        if trimmed == "~" || trimmed.hasPrefix("~/") { return LaunchQuery(raw: raw, term: trimmed, isPath: true) }
        if first == "/" {
            // "/" lists the prefixes, "/calc" filters them, "/Users" or "/a/b" is a path.
            if rest.contains("/") || (!rest.isEmpty && pathExists(trimmed)) {
                return LaunchQuery(raw: raw, term: trimmed, isPath: true)
            }
            return LaunchQuery(raw: raw, prefix: .providers, term: rest)
        }
        guard let prefix = Prefix(rawValue: String(first)) else { return LaunchQuery(raw: raw) }
        // ".5 * 2" and "$40 in usd" are sums, not files and clipboard.
        if prefix == .files || prefix == .clipboard, let second, second.isNumber {
            return LaunchQuery(raw: raw)
        }
        return LaunchQuery(raw: raw, prefix: prefix, term: rest)
    }
}
