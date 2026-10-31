import Foundation

/// One candidate during a search.
struct Hit: Sendable {
    let index: Int32
    let tier: MatchTier
    let quality: UInt8
    let boost: Float
    let depth: UInt16
    let length: UInt16

    /// Tier first, then match quality, then use, then shallower, then shorter.
    static func ranksBefore(_ a: Hit, _ b: Hit) -> Bool {
        if a.tier != b.tier { return a.tier < b.tier }
        if a.quality != b.quality { return a.quality > b.quality }
        if a.boost != b.boost { return a.boost > b.boost }
        if a.depth != b.depth { return a.depth < b.depth }
        if a.length != b.length { return a.length < b.length }
        return a.index < b.index
    }
}

/// What one slice of a search found: the best hits, and every entry that matched,
/// which the next keystroke can search again instead of the whole index.
struct ScanResult: Sendable {
    var hits: [Hit] = []
    var matched: [Int32] = []
}

/// Scans a slice of the index. The search runs one of these per core.
enum IndexSearch {
    /// Scans `range` of the index, or of `candidates` when given (entries a
    /// shorter query matched).
    static func scan(
        _ storage: IndexStorage, _ query: SearchQuery, _ range: Range<Int>,
        candidates: [Int32]? = nil, limit: Int
    ) -> ScanResult {
        var result = ScanResult()
        let cap = limit * 4 + 64
        var noRanges: [Range<Int>]? = nil
        let wanted = query.mask
        let words = query.words
        let ids = candidates ?? []
        query.bytes.withUnsafeBufferPointer { queryBytes in
        storage.folded.withUnsafeBufferPointer { folded in
        storage.names.withUnsafeBufferPointer { names in
        storage.flags.withUnsafeBufferPointer { flagList in
        storage.mask.withUnsafeBufferPointer { masks in
        storage.foldStart.withUnsafeBufferPointer { foldStarts in
        storage.foldLength.withUnsafeBufferPointer { foldLengths in
        ids.withUnsafeBufferPointer { ids in
            for k in range {
                let i = candidates == nil ? k : Int(ids[k])
                let flags = flagList[i]
                if flags & IndexStorage.removedFlag != 0 { continue }
                if masks[i] & wanted != wanted { continue }
                let foldStart = Int(foldStarts[i])
                let name = UnsafeBufferPointer(rebasing: folded[foldStart..<(foldStart + Int(foldLengths[i]))])
                var original: UnsafeBufferPointer<UInt8>? = nil
                if flags & IndexStorage.asciiFlag != 0 {
                    let nameStart = Int(storage.nameStart[i])
                    original = UnsafeBufferPointer(rebasing: names[nameStart..<(nameStart + Int(storage.nameLength[i]))])
                }
                guard let rank = NameMatcher.match(
                    name, original: original, query: queryBytes, words: words, ranges: &noRanges
                ) else { continue }
                result.matched.append(Int32(i))
                result.hits.append(Hit(
                    index: Int32(i), tier: rank.tier, quality: rank.quality,
                    boost: storage.boost[i], depth: storage.depth[i], length: foldLengths[i]
                ))
                if result.hits.count >= cap {
                    result.hits.sort(by: Hit.ranksBefore)
                    result.hits.removeSubrange(limit...)
                }
            }
        }
        }
        }
        }
        }
        }
        }
        }
        result.hits.sort(by: Hit.ranksBefore)
        if result.hits.count > limit { result.hits.removeSubrange(limit...) }
        return result
    }

    /// The matched byte ranges of one result, as UTF-16 offsets into its name.
    static func highlights(_ storage: IndexStorage, _ index: Int, _ query: SearchQuery) -> [Range<Int>] {
        var ranges: [Range<Int>]? = []
        let ascii = storage.flags[index] & IndexStorage.asciiFlag != 0
        query.bytes.withUnsafeBufferPointer { queryBytes in
            storage.folded.withUnsafeBufferPointer { folded in
                storage.names.withUnsafeBufferPointer { names in
                    let foldStart = Int(storage.foldStart[index])
                    let name = UnsafeBufferPointer(rebasing: folded[foldStart..<(foldStart + Int(storage.foldLength[index]))])
                    var original: UnsafeBufferPointer<UInt8>? = nil
                    if ascii {
                        let nameStart = Int(storage.nameStart[index])
                        original = UnsafeBufferPointer(rebasing: names[nameStart..<(nameStart + Int(storage.nameLength[index]))])
                    }
                    _ = NameMatcher.match(name, original: original, query: queryBytes, words: query.words, ranges: &ranges)
                }
            }
        }
        let merged = merge(ranges ?? [])
        return ascii ? merged : utf16(merged, in: storage.name(index))
    }

    static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Maps folded byte offsets to UTF-16 offsets of the original name, one character at a time.
    static func utf16(_ ranges: [Range<Int>], in name: String) -> [Range<Int>] {
        var characters: [(byte: Int, bytes: Int, utf16: Int, units: Int)] = []
        var byte = 0
        var unit = 0
        for character in name {
            let bytes = NameFold.fold(character).count
            let units = character.utf16.count
            characters.append((byte, bytes, unit, units))
            byte += bytes
            unit += units
        }
        func character(containing offset: Int) -> Int {
            var low = 0
            var high = characters.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if characters[mid].byte <= offset { low = mid } else { high = mid - 1 }
            }
            return low
        }
        guard !characters.isEmpty else { return [] }
        return merge(ranges.compactMap { range in
            guard !range.isEmpty else { return nil }
            let first = characters[character(containing: range.lowerBound)]
            let last = characters[character(containing: range.upperBound - 1)]
            return first.utf16..<(last.utf16 + last.units)
        })
    }
}
