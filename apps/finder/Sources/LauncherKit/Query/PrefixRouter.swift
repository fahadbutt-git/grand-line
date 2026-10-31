import Foundation

/// Reads the first character of a query: a prefix sends it to one provider, a
/// path goes to the path provider, anything else searches everything.
public struct PrefixRouter: Sendable {
    let pathExists: @Sendable (String) -> Bool
    /// Whether `:` reads the clipboard history (Maccy's store is there). Without
    /// it, `:` keeps its older meaning, the symbols.
    let clipboardHistory: @Sendable () -> Bool

    public init(pathExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                clipboardHistory: @escaping @Sendable () -> Bool = { ClipboardHistory.isAvailable() }) {
        self.pathExists = pathExists
        self.clipboardHistory = clipboardHistory
    }

    public func parse(_ text: String) -> LaunchQuery {
        let raw = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return LaunchQuery(raw: raw) }
        let rest = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let second = trimmed.dropFirst().first

        if trimmed == "~" || trimmed.hasPrefix("~/") { return LaunchQuery(raw: raw, term: trimmed, isPath: true) }
        if trimmed.hasPrefix("::") {
            return LaunchQuery(raw: raw, prefix: .symbols, term: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        switch first {
        case "/":
            // "/a/b" or an existing "/Users" is a path, "/" alone lists the
            // prefixes, "/ " or "/glauc" searches files.
            if rest.contains("/") || (!rest.isEmpty && second != " " && pathExists(trimmed)) {
                return LaunchQuery(raw: raw, term: trimmed, isPath: true)
            }
            let leading = text.drop(while: { $0 == " " })
            if rest.isEmpty && !leading.hasPrefix("/ ") { return LaunchQuery(raw: raw, prefix: .providers, term: "") }
            return LaunchQuery(raw: raw, prefix: .files, term: rest)
        case ":":
            return LaunchQuery(raw: raw, prefix: clipboardHistory() ? .clipboardHistory : .symbols, term: rest)
        case "!", "<":
            return LaunchQuery(raw: raw, prefix: .windows, term: rest)
        default:
            break
        }
        guard let prefix = Prefix(rawValue: String(first)) else { return LaunchQuery(raw: raw) }
        // ".5 * 2", "$40 in usd" and ",5" are sums, not files, clipboard and settings.
        if prefix == .files || prefix == .clipboard || prefix == .settings, let second, second.isNumber {
            return LaunchQuery(raw: raw)
        }
        return LaunchQuery(raw: raw, prefix: prefix, term: rest)
    }
}
