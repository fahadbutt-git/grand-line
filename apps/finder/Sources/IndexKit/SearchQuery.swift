import Foundation

/// A typed query, folded like the names. Words are separated by single spaces in
/// `bytes`, and each word's range is in `words`.
struct SearchQuery: Sendable {
    let bytes: [UInt8]
    let words: [Range<Int>]
    let mask: UInt64

    init?(_ text: String) {
        var bytes: [UInt8] = []
        var words: [Range<Int>] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            let folded = NameFold.fold(String(word))
            guard !folded.isEmpty else { continue }
            if !bytes.isEmpty { bytes.append(NameFold.space) }
            words.append(bytes.count..<(bytes.count + folded.count))
            bytes += folded
        }
        guard !words.isEmpty else { return nil }
        self.bytes = bytes
        self.words = words
        self.mask = NameFold.mask(bytes)
    }

    /// Whether every name this query matches is sure to match `earlier` too: the
    /// earlier words are all here unchanged except the last, which this query may
    /// lengthen, and words may follow. Typing on from a query always narrows it.
    func narrows(_ earlier: SearchQuery) -> Bool {
        guard words.count >= earlier.words.count else { return false }
        let last = earlier.words.count - 1
        for k in 0...last {
            let old = earlier.bytes[earlier.words[k]]
            let new = bytes[words[k]]
            if k == last {
                guard new.starts(with: old) else { return false }
            } else {
                guard new.elementsEqual(old) else { return false }
            }
        }
        return true
    }
}
