import Foundation

/// Quoting for /bin/bash -c lines.
public enum ShellQuote {
    /// 'it'\''s' style: safe for any text.
    public static func quote(_ text: String) -> String {
        if !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0) }), text.unicodeScalars.allSatisfy(\.isASCII) {
            return text
        }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func line(_ words: [String]) -> String {
        words.map(quote).joined(separator: " ")
    }
}
