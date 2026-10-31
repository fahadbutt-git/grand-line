import Foundation

/// Ranks one folded name against a query. Pass `ranges` to also collect the matched
/// byte ranges, which the search does only for the results it returns.
enum NameMatcher {
    typealias Bytes = UnsafeBufferPointer<UInt8>

    struct Rank: Equatable {
        var tier: MatchTier
        /// Breaks ties inside a tier. A fuzzy word scores up to 31 for word starts and
        /// adjacent letters; in a query of several words, each word that matched
        /// better than fuzzy adds 32 to 128, so "glau rn" puts a name that starts with
        /// "glau" above names where both words only match fuzzily.
        var quality: UInt8 = 0
    }

    static func match(
        _ name: Bytes,
        original: Bytes?,
        query: Bytes,
        words: [Range<Int>],
        ranges: inout [Range<Int>]?
    ) -> Rank? {
        if words.count == 1 {
            return matchWord(name, original, query, &ranges, fuzzy: true)
        }
        if let whole = matchWord(name, original, query, &ranges, fuzzy: false) {
            return whole
        }
        var worst = MatchTier.exact
        var quality = 0
        for word in words {
            guard let rank = matchWord(name, original, Bytes(rebasing: query[word]), &ranges, fuzzy: true) else {
                return nil
            }
            worst = max(worst, rank.tier)
            quality += rank.tier == .fuzzy ? Int(rank.quality) : 32 * (4 - rank.tier.rawValue)
        }
        return Rank(tier: worst, quality: UInt8(min(quality, 255)))
    }

    static func matchWord(
        _ name: Bytes,
        _ original: Bytes?,
        _ word: Bytes,
        _ ranges: inout [Range<Int>]?,
        fuzzy: Bool
    ) -> Rank? {
        let length = word.count
        guard length > 0, length <= name.count else { return nil }

        if occurs(word, in: name, at: 0) {
            ranges?.append(0..<length)
            let isWhole = length == name.count
            let isStem = length < name.count && name[length] == NameFold.dot && lastDot(name) == length
            return Rank(tier: isWhole || isStem ? .exact : .prefix)
        }

        var first = -1
        var from = 1
        while let index = find(word, in: name, from: from) {
            if NameFold.isBoundary(name, original, index) {
                ranges?.append(index..<(index + length))
                return Rank(tier: .wordStart)
            }
            if first < 0 { first = index }
            from = index + 1
        }
        if first >= 0 {
            ranges?.append(first..<(first + length))
            return Rank(tier: .substring)
        }
        return fuzzy ? subsequence(name, original, word, &ranges) : nil
    }

    /// Letters in order. The first letter must start a word. Each later letter takes,
    /// in order of preference, the next position, a word start, or the next occurrence.
    static func subsequence(_ name: Bytes, _ original: Bytes?, _ word: Bytes, _ ranges: inout [Range<Int>]?) -> Rank? {
        guard isSubsequence(word, from: 0, of: name, from: 0) else { return nil }
        var cursor = 0
        var starts = 0
        var adjacent = 0
        var picked: [Int] = []
        for k in 0..<word.count {
            let letter = word[k]
            var chosen = -1
            if k > 0, cursor < name.count, name[cursor] == letter,
               isSubsequence(word, from: k + 1, of: name, from: cursor + 1) {
                chosen = cursor
                adjacent += 1
            }
            if chosen < 0 {
                var i = cursor
                while i < name.count {
                    if name[i] == letter, NameFold.isBoundary(name, original, i),
                       isSubsequence(word, from: k + 1, of: name, from: i + 1) {
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
            if ranges != nil { picked.append(chosen) }
            cursor = chosen + 1
        }
        if ranges != nil {
            var runs: [Range<Int>] = []
            for position in picked {
                if let last = runs.last, last.upperBound == position {
                    runs[runs.count - 1] = last.lowerBound..<(position + 1)
                } else {
                    runs.append(position..<(position + 1))
                }
            }
            ranges?.append(contentsOf: runs)
        }
        return Rank(tier: .fuzzy, quality: UInt8(min(starts * 4 + adjacent, 31)))
    }

    @inline(__always)
    static func occurs(_ word: Bytes, in name: Bytes, at start: Int) -> Bool {
        guard start + word.count <= name.count else { return false }
        var j = 0
        while j < word.count {
            if name[start + j] != word[j] { return false }
            j += 1
        }
        return true
    }

    static func find(_ word: Bytes, in name: Bytes, from start: Int) -> Int? {
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

    static func isSubsequence(_ word: Bytes, from k: Int, of name: Bytes, from start: Int) -> Bool {
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

    static func lastDot(_ name: Bytes) -> Int? {
        var i = name.count - 1
        while i > 0 {
            if name[i] == NameFold.dot { return i }
            i -= 1
        }
        return nil
    }
}
