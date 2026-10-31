import Foundation

/// A config/themes/<name>.theme file: KEY=value lines, values optionally quoted,
/// # comments. This reads one file as written; loading a theme goes through
/// `ThemeSource.resolve(url:)` and `ThemeSpec.validate`, which follow EXTENDS,
/// fill the defaults and check the values.
public enum ThemeFile {
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    public static func read(_ url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }
}
