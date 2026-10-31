import Foundation
import IndexKit

/// Matches a query against folded titles and keywords, in IndexKit's tiers:
/// exact, prefix, word start, substring, then fuzzy (letters in order, the first
/// at a word start, so "vsc" finds "Visual Studio Code").
public struct TextMatcher: Sendable {
    public let query: FoldedText
    let words: [[UInt8]]
    /// The `'` prefix: no fuzzy matches.
    public let exactOnly: Bool

    public init(_ text: String, exactOnly: Bool = false) {
        let folded = FoldedText(text.trimmingCharacters(in: .whitespaces))
        self.query = folded
        self.exactOnly = exactOnly
        self.words = folded.bytes.split(separator: UInt8(ascii: " ")).map(Array.init)
    }

    public var isEmpty: Bool { words.isEmpty }

    public struct Hit: Sendable, Equatable {
        public var tier: MatchTier
        public var quality: Int
        public var ranges: [Range<Int>]
    }

    /// Matches the whole query first, then each word on its own (all must match).
    public func match(_ text: FoldedText) -> Hit? {
        guard !words.isEmpty else { return nil }
        if let whole = matchWord(query.bytes, in: text, fuzzy: words.count == 1) {
            return whole
        }
        guard words.count > 1 else { return nil }
        var worst = MatchTier.exact
        var quality = 0
        var ranges: [Range<Int>] = []
        for word in words {
            guard let hit = matchWord(word, in: text, fuzzy: true) else { return nil }
            worst = max(worst, hit.tier == .exact ? .prefix : hit.tier)
            quality += hit.tier == .fuzzy ? hit.quality : 32 * (4 - hit.tier.rawValue)
            ranges += hit.ranges
        }
        return Hit(tier: worst, quality: quality, ranges: ranges)
    }

    /// The best tier of any of the texts, for keywords.
    public func bestMatch(_ texts: [FoldedText]) -> Hit? {
        var best: Hit?
        for text in texts {
            guard let hit = match(text) else { continue }
            if best == nil || hit.tier < best!.tier || (hit.tier == best!.tier && hit.quality > best!.quality) {
                best = hit
            }
        }
        return best
    }

    /// Highlights of a hit as UTF-16 ranges of the original title.
    public func highlights(_ hit: Hit, in text: FoldedText) -> [Range<Int>] {
        hit.ranges.map { text.utf16Range($0) }.sorted { $0.lowerBound < $1.lowerBound }
    }

    func matchWord(_ word: [UInt8], in text: FoldedText, fuzzy: Bool) -> Hit? {
        let name = text.bytes
        let length = word.count
        guard length > 0, length <= name.count else { return nil }

        if occurs(word, in: name, at: 0) {
            let whole = length == name.count || length == text.stemLength
            return Hit(tier: whole ? .exact : .prefix, quality: 0, ranges: [0..<length])
        }
        var first = -1
        var from = 1
        while let index = find(word, in: name, from: from) {
            if text.starts[index] { return Hit(tier: .wordStart, quality: 0, ranges: [index..<(index + length)]) }
            if first < 0 { first = index }
            from = index + 1
        }
        if first >= 0 { return Hit(tier: .substring, quality: 0, ranges: [first..<(first + length)]) }
        guard fuzzy, !exactOnly else { return nil }
        return subsequence(word, in: text)
    }

    /// Letters in order, the first at a word start. Later letters prefer the next
    /// position, then a word start, then the next occurrence.
    func subsequence(_ word: [UInt8], in text: FoldedText) -> Hit? {
        let name = text.bytes
        var cursor = 0
        var picked: [Int] = []
        var starts = 0
        var adjacent = 0
        for k in 0..<word.count {
            let letter = word[k]
            var chosen = -1
            if k > 0, cursor < name.count, name[cursor] == letter, isSubsequence(word, k + 1, name, cursor + 1) {
                chosen = cursor
                adjacent += 1
            }
            if chosen < 0 {
                var i = cursor
                while i < name.count {
                    if name[i] == letter, text.starts[i], isSubsequence(word, k + 1, name, i + 1) {
                        chosen = i
                        starts += 1
                        break
                    }
                    i += 1
                }
            }
            if chosen < 0 {
                if k == 0 { return nil }
                var i = cursor
                while i < name.count, name[i] != letter { i += 1 }
                guard i < name.count else { return nil }
                chosen = i
            }
            picked.append(chosen)
            cursor = chosen + 1
        }
        var runs: [Range<Int>] = []
        for position in picked {
            if let last = runs.last, last.upperBound == position {
                runs[runs.count - 1] = last.lowerBound..<(position + 1)
            } else {
                runs.append(position..<(position + 1))
            }
        }
        return Hit(tier: .fuzzy, quality: min(starts * 4 + adjacent, 31), ranges: runs)
    }

    @inline(__always)
    func occurs(_ word: [UInt8], in name: [UInt8], at start: Int) -> Bool {
        guard start + word.count <= name.count else { return false }
        for j in 0..<word.count where name[start + j] != word[j] { return false }
        return true
    }

    func find(_ word: [UInt8], in name: [UInt8], from start: Int) -> Int? {
        let last = name.count - word.count
        guard start <= last else { return nil }
        let head = word[0]
        var i = start
        while i <= last {
            if name[i] == head, occurs(word, in: name, at: i) { return i }
            i += 1
        }
        return nil
    }

    func isSubsequence(_ word: [UInt8], _ k: Int, _ name: [UInt8], _ start: Int) -> Bool {
        var k = k
        var i = start
        while k < word.count {
            while i < name.count, name[i] != word[k] { i += 1 }
            if i == name.count { return false }
            i += 1
            k += 1
        }
        return true
    }
}
