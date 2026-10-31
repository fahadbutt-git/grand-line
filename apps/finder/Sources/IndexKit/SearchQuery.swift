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
}
