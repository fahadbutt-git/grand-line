import Foundation
import IndexKit

/// Matches a query against folded titles and keywords, in IndexKit's tiers:
/// exact, prefix, word start, substring, then fuzzy (letters in order, the first
/// at a word start, so "vsc" finds "Visual Studio Code"). The tier decides the
/// rank; inside a tier, fzf's score (FuzzyScore) is the quality. A bitmask of
/// the letters in each text skips texts that lack one of the query's letters
/// before any matching is done.
public struct TextMatcher: Sendable {
    public let query: FoldedText
    let words: [[UInt8]]
    /// The letters of every word: a text without one of them cannot match.
    let lettersMask: UInt64
    /// The `'` prefix: no fuzzy matches.
    public let exactOnly: Bool

    public init(_ text: String, exactOnly: Bool = false) {
        let folded = FoldedText(text.trimmingCharacters(in: .whitespaces))
        self.query = folded
        self.exactOnly = exactOnly
        self.words = folded.bytes.split(separator: UInt8(ascii: " ")).map(Array.init)
        self.lettersMask = TextFold.mask(folded.bytes.lazy.filter { $0 != UInt8(ascii: " ") })
    }

    public var isEmpty: Bool { words.isEmpty }

    public struct Hit: Sendable, Equatable {
        public var tier: MatchTier
        /// fzf's score: higher is better.
        public var quality: Int
        public var ranges: [Range<Int>]
    }

    /// Whether the text could match at all (the prefilter).
    @inline(__always)
    public func mayMatch(_ text: FoldedText) -> Bool {
        lettersMask & ~text.mask == 0
    }

    /// Matches the whole query first, then each word on its own (all must match).
    public func match(_ text: FoldedText) -> Hit? {
        guard !words.isEmpty, mayMatch(text) else { return nil }
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
            quality += hit.quality
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
            return Hit(tier: whole ? .exact : .prefix, quality: FuzzyScore.contiguous(0, length: length, in: text), ranges: [0..<length])
        }
        // The best-scoring occurrence: a word start beats one inside a word.
        var best: (index: Int, score: Int)?
        var atStart = false
        var from = 1
        while let index = find(word, in: name, from: from) {
            let score = FuzzyScore.contiguous(index, length: length, in: text)
            let starts = text.starts[index]
            if best == nil || (starts && !atStart) || (starts == atStart && score > best!.score) {
                best = (index, score)
                atStart = starts
            }
            from = index + 1
        }
        if let best {
            return Hit(tier: atStart ? .wordStart : .substring, quality: best.score, ranges: [best.index..<(best.index + length)])
        }
        guard fuzzy, !exactOnly else { return nil }
        return subsequence(word, in: text)
    }

    /// Letters in order, the first at a word start, placed where fzf's score is highest.
    func subsequence(_ word: [UInt8], in text: FoldedText) -> Hit? {
        guard let found = FuzzyScore.best(word, in: text) else { return nil }
        var runs: [Range<Int>] = []
        for position in found.positions {
            if let last = runs.last, last.upperBound == position {
                runs[runs.count - 1] = last.lowerBound..<(position + 1)
            } else {
                runs.append(position..<(position + 1))
            }
        }
        return Hit(tier: .fuzzy, quality: found.score, ranges: runs)
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
