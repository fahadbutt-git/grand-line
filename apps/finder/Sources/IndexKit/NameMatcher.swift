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
        isFolder: Bool = false,
        ranges: inout [Range<Int>]?
    ) -> Rank? {
        if words.count == 1 {
            return matchWord(name, original, query, &ranges, fuzzy: true, isFolder: isFolder)
        }
        if let whole = matchWord(name, original, query, &ranges, fuzzy: false, isFolder: isFolder) {
            return whole
        }
        var worst = MatchTier.exact
        var quality = 0
        for word in words {
            guard let rank = matchWord(name, original, Bytes(rebasing: query[word]), &ranges, fuzzy: true, isFolder: isFolder) else {
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
        fuzzy: Bool,
        isFolder: Bool = false
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
        return fuzzy ? subsequence(name, original, word, isFolder: isFolder, &ranges) : nil
    }

    // MARK: Tight fuzzy matches

    /// Letters inside one word may skip at most this many letters between
    /// them ("spf" in "System Preferences" skips two). Sight's matcher
    /// (LauncherKit's TextMatcher) uses the same limits.
    static let maxGapInWord = 3
    /// Words skipped between two words the match uses, at most.
    static let maxSkippedWords = 2
    /// Placements tried for one name before it is given up as no match, so a
    /// name made of one repeated letter cannot make a search slow.
    static let fuzzyBudget = 256

    /// Letters in order, close together, in the name without its extension.
    ///
    /// - The first letter starts a word, and a letter that moves on to another
    ///   word takes that word's first letter, skipping at most
    ///   `maxSkippedWords` words.
    /// - Letters inside one word skip at most `maxGapInWord` letters.
    /// - A match leaves a word for the next only when the letters it took
    ///   there are that word's start ("glau" of Glaucoma, then "r" of Review):
    ///   "conj" is not "co" and an "n" further into "combined", then a "J".
    /// - A file's extension never takes part: ".json" gives no "j".
    ///
    /// Each letter prefers the next position, then the start of a following
    /// word, then a later letter in the same word. Letters scattered through a
    /// long name ("conj" in "Astigmatic Refractive Correction - Jackson
    /// Cross.pdf") are not a match.
    static func subsequence(_ full: Bytes, _ original: Bytes?, _ word: Bytes, isFolder: Bool = false,
                            _ ranges: inout [Range<Int>]?) -> Rank? {
        let end = isFolder ? full.count : (extensionStart(full) ?? full.count)
        guard word.count > 0, word.count <= end else { return nil }
        let name = Bytes(rebasing: full[0..<end])
        guard isSubsequence(word, from: 0, of: name, from: 0) else { return nil }
        var search = FuzzySearch(name: name, original: original, word: word, keepsPositions: ranges != nil)
        for first in 0..<name.count where name[first] == word[0] && NameFold.isBoundary(name, original, first) {
            guard search.budget > 0 else { return nil }
            search.starts = 1
            search.adjacent = 0
            search.picked.removeAll(keepingCapacity: true)
            if search.keepsPositions { search.picked.append(first) }
            guard search.place(1, after: first, gapped: false) else { continue }
            if ranges != nil {
                var runs: [Range<Int>] = []
                for position in search.picked {
                    if let last = runs.last, last.upperBound == position {
                        runs[runs.count - 1] = last.lowerBound..<(position + 1)
                    } else {
                        runs.append(position..<(position + 1))
                    }
                }
                ranges?.append(contentsOf: runs)
            }
            return Rank(tier: .fuzzy, quality: UInt8(min(search.starts * 4 + search.adjacent, 31)))
        }
        return nil
    }

    /// Where a file's extension starts (its dot): the last dot after the first
    /// byte, followed by one to ten letters or digits. "v1.0_302141.zip" gives
    /// the dot of ".zip"; "Dr. Lee notes" has none.
    static func extensionStart(_ name: Bytes) -> Int? {
        guard let dot = lastDot(name) else { return nil }
        let length = name.count - dot - 1
        guard (1...10).contains(length) else { return nil }
        for i in (dot + 1)..<name.count where !NameFold.isWordByte(name[i]) { return nil }
        return dot
    }

    /// A depth-first placement of a word's letters under the rules of
    /// `subsequence`, with its score.
    struct FuzzySearch {
        let name: Bytes
        let original: Bytes?
        let word: Bytes
        let keepsPositions: Bool
        var budget = NameMatcher.fuzzyBudget
        var starts = 0
        var adjacent = 0
        var picked: [Int] = []

        init(name: Bytes, original: Bytes?, word: Bytes, keepsPositions: Bool) {
            self.name = name
            self.original = original
            self.word = word
            self.keepsPositions = keepsPositions
        }

        @inline(__always)
        func startsWord(_ i: Int) -> Bool {
            NameFold.isWordByte(name[i]) && NameFold.isBoundary(name, original, i)
        }

        /// Places letter `k` and the rest after position `previous`. `gapped`
        /// is whether a letter was skipped in the word `previous` is in.
        mutating func place(_ k: Int, after previous: Int, gapped: Bool) -> Bool {
            if k == word.count { return true }
            budget -= 1
            guard budget > 0 else { return false }
            let letter = word[k]
            let next = previous + 1
            guard next < name.count else { return false }
            // The next position: in the same word, or a following word's start.
            if name[next] == letter {
                let crosses = startsWord(next)
                if !crosses || !gapped {
                    if take(next, k, adjacent: true, start: false, gapped: crosses ? false : gapped) { return true }
                }
            }
            // The start of a following word, when this word's letters were its start.
            if !gapped {
                var entered = 0
                var i = next
                while i < name.count {
                    if startsWord(i) {
                        entered += 1
                        if entered - 1 > NameMatcher.maxSkippedWords { break }
                        if i != next, name[i] == letter,
                           take(i, k, adjacent: false, start: true, gapped: false) { return true }
                    }
                    i += 1
                }
            }
            // A later letter in the same word (not when the word ends here).
            guard !startsWord(next) else { return false }
            var i = next + 1
            while i < name.count, i - previous - 1 <= NameMatcher.maxGapInWord, !startsWord(i) {
                if name[i] == letter, take(i, k, adjacent: false, start: false, gapped: true) { return true }
                i += 1
            }
            return false
        }

        private mutating func take(_ position: Int, _ k: Int, adjacent isAdjacent: Bool, start isStart: Bool, gapped: Bool) -> Bool {
            if isAdjacent { adjacent += 1 }
            if isStart { starts += 1 }
            if keepsPositions { picked.append(position) }
            if place(k + 1, after: position, gapped: gapped) { return true }
            if isAdjacent { adjacent -= 1 }
            if isStart { starts -= 1 }
            if keepsPositions { picked.removeLast() }
            return false
        }
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
