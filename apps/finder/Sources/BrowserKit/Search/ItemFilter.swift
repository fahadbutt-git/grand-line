import Foundation

/// The omnibar's filter (nnn's type-to-nav, XYplorer's visual filter): a row
/// stays when its name holds every typed word, ignoring case and accents. A
/// word starting with `*` or holding `*` or `?` is a wildcard pattern for the
/// whole name instead ("*.pdf").
public enum ItemFilter {
    public static func matches(_ name: String, _ filter: String) -> Bool {
        let words = filter.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let folded = fold(name)
        return words.allSatisfy { word in
            if word.contains("*") || word.contains("?") { return wildcard(fold(word), folded) }
            return folded.contains(fold(word))
        }
    }

    static func fold(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `*` any run of characters, `?` one character, matched against the whole name.
    static func wildcard(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern)
        let n = Array(name)
        var pi = 0, ni = 0
        var star = -1, mark = 0
        while ni < n.count {
            if pi < p.count, p[pi] == "?" || p[pi] == n[ni] {
                pi += 1
                ni += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi
                mark = ni
                pi += 1
            } else if star >= 0 {
                pi = star + 1
                mark += 1
                ni = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
