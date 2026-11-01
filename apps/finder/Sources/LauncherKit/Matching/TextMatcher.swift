import Foundation
import IndexKit

/// Matches a query against folded titles and keywords, in IndexKit's tiers:
/// exact, prefix, word start, substring, then fuzzy (letters in order, the first
/// at a word start, so "vsc" finds "Visual Studio Code"), then typo (one letter
/// off at a word start, for words of four letters or more: "safri" finds
/// "Safari"). The tier decides the rank; inside a tier, fzf's score
/// (FuzzyScore) is the quality. A bitmask of the letters in each text skips
/// texts that lack one of the query's letters before any matching is done.
///
/// A fuzzy match must be tight (see `isTight`): each word it touches is
/// entered at its first letter, letters inside a word are close together, and
/// it skips at most two words between the words it uses. Letters scattered
/// through a long title ("sleep" in "How to study for USMLE Step 1") are not a match.
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

    /// Whether a text missing some of the query's letters could still match
    /// with a typo: at most one letter missing for each word long enough to
    /// have one.
    func mayMatchWithTypo(_ text: FoldedText) -> Bool {
        guard !exactOnly else { return false }
        let typoWords = words.filter { $0.count >= Self.typoMinimum }.count
        guard typoWords > 0 else { return false }
        return (lettersMask & ~text.mask).nonzeroBitCount <= typoWords
    }

    /// Matches the whole query first, then each word on its own (all must match).
    public func match(_ text: FoldedText) -> Hit? {
        guard !words.isEmpty, mayMatch(text) || mayMatchWithTypo(text) else { return nil }
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
        guard length > 0 else { return nil }
        // One letter longer than the whole text can still be a typo ("safarri").
        guard length <= name.count else { return fuzzy && length == name.count + 1 ? typo(word, in: text) : nil }

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
        return subsequence(word, in: text) ?? typo(word, in: text)
    }

    /// Letters in order, the first at a word start, placed where fzf's score
    /// is highest, and close together (`isTight`).
    func subsequence(_ word: [UInt8], in text: FoldedText) -> Hit? {
        guard let found = FuzzyScore.best(word, in: text), Self.isTight(found.positions, in: text) else { return nil }
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

    // MARK: Tight fuzzy matches

    /// Letters inside one word may skip at most this many letters between them
    /// ("spf" in "System Preferences" skips two).
    static let maxGapInWord = 3
    /// Words skipped between two words the match uses ("pdf ex" style
    /// abbreviations of "PDF to Excel"), at most.
    static let maxSkippedWords = 2

    /// Whether letters at `positions` (ascending) form a tight match: the
    /// first letter of each word touched is that word's first letter, letters
    /// in the same word are at most `maxGapInWord` apart, and no more than
    /// `maxSkippedWords` words lie between two words touched.
    static func isTight(_ positions: [Int], in text: FoldedText) -> Bool {
        guard let first = positions.first, text.starts[first] else { return false }
        var word = 0
        var cursor = 0
        // The word index of each byte up to `position`, counted as we go.
        func wordIndex(_ position: Int) -> Int {
            while cursor < position {
                cursor += 1
                if text.starts[cursor] { word += 1 }
            }
            return word
        }
        var previous = first
        var previousWord = wordIndex(first)
        for position in positions.dropFirst() {
            let current = wordIndex(position)
            if current == previousWord {
                if position - previous - 1 > maxGapInWord { return false }
            } else {
                if !text.starts[position] { return false }
                if current - previousWord - 1 > maxSkippedWords { return false }
            }
            previous = position
            previousWord = current
        }
        return true
    }

    // MARK: Typos

    /// Words shorter than this are never matched with a typo: too many short
    /// words are one letter apart.
    static let typoMinimum = 4

    /// The word one edit away from what was typed (a letter missed, added,
    /// changed, or two swapped), at the start of a word in the text, with the
    /// same first letter. Ranked below every other tier.
    func typo(_ word: [UInt8], in text: FoldedText) -> Hit? {
        guard !exactOnly, word.count >= Self.typoMinimum else { return nil }
        let name = text.bytes
        var best: (start: Int, length: Int, score: Int)?
        for start in name.indices where text.starts[start] && name[start] == word[0] {
            guard let length = Self.prefixWithinOneEdit(word, of: name, from: start) else { continue }
            let score = FuzzyScore.contiguous(start, length: length, in: text) - FuzzyScore.scoreMatch * 2
            if best == nil || score > best!.score { best = (start, length, score) }
        }
        guard let best else { return nil }
        return Hit(tier: .typo, quality: best.score, ranges: [best.start..<(best.start + best.length)])
    }

    /// The length of the shortest stretch of `name` from `start` that is one
    /// edit (Damerau: insert, delete, change, swap two neighbours) from `word`,
    /// or nil when every stretch is further. Distance 0 is not a typo (an
    /// earlier tier has it).
    static func prefixWithinOneEdit(_ word: [UInt8], of name: [UInt8], from start: Int) -> Int? {
        let m = word.count
        let available = name.count - start
        guard available >= m - 1 else { return nil }
        let n = min(available, m + 1)
        // d[i][j]: edits between word[..<i] and name[start..<start+j].
        let width = n + 1
        var d = [Int](repeating: 0, count: (m + 1) * width)
        for i in 0...m { d[i * width] = i }
        for j in 0...n { d[j] = j }
        if m >= 1, n >= 1 {
            for i in 1...m {
                var rowMinimum = Int.max
                for j in 1...n {
                    let same = word[i - 1] == name[start + j - 1]
                    var value = min(d[(i - 1) * width + j] + 1, d[i * width + j - 1] + 1, d[(i - 1) * width + j - 1] + (same ? 0 : 1))
                    if i > 1, j > 1, word[i - 1] == name[start + j - 2], word[i - 2] == name[start + j - 1] {
                        value = min(value, d[(i - 2) * width + j - 2] + 1)
                    }
                    d[i * width + j] = value
                    rowMinimum = min(rowMinimum, value)
                }
                if rowMinimum > 1 { return nil }
            }
        }
        for j in max(m - 1, 1)...n where d[m * width + j] == 1 {
            return j
        }
        return nil
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
