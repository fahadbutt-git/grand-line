import Foundation

/// Tab-separated config files: one row per line, # starts a comment line.
public enum TSV {
    public static func rows(_ text: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            return line.split(separator: "\t", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
    }
}
