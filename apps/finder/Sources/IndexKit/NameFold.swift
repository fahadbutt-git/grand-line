// The character bitmask prefilter and the word boundary rules are adapted from
// ordo-one/FuzzyMatch (Apache-2.0), Prefilters.swift and WordBoundary.swift.
import Foundation

/// Names are matched in folded form: composed (NFC), lowercase and without
/// accents, so "resume" finds "Résumé" whether the disk stored the name composed
/// or decomposed (NFD, as older HFS+ volumes and many sync tools write it), and
/// a decomposed Hangul syllable finds the composed one typed in a query. ASCII
/// names, the usual case, fold byte for byte.
enum NameFold {
    static let space: UInt8 = 0x20
    static let dot: UInt8 = 0x2E

    static func fold(_ text: String) -> [UInt8] {
        if isASCII(text) { return text.utf8.map(lower) }
        var folded: [UInt8] = []
        folded.reserveCapacity(text.utf8.count)
        for character in text {
            folded.append(contentsOf: fold(character))
        }
        return folded
    }

    /// Folding one character at a time keeps a map from folded bytes back to characters.
    static func fold(_ character: Character) -> [UInt8] {
        if let ascii = character.asciiValue, character.utf8.count == 1 {
            return [lower(ascii)]
        }
        let composed = String(character).precomposedStringWithCanonicalMapping
        let folded = composed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        return Array(folded.precomposedStringWithCanonicalMapping.utf8)
    }

    static func isASCII(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 0x80 }
    }

    @inline(__always)
    static func lower(_ byte: UInt8) -> UInt8 {
        (byte >= 0x41 && byte <= 0x5A) ? byte | 0x20 : byte
    }

    /// One bit per letter and digit, shared bits for punctuation, one bit for any
    /// non-ASCII byte. A name can only match when it has every bit of the query.
    static func mask<S: Sequence>(_ bytes: S) -> UInt64 where S.Element == UInt8 {
        var mask: UInt64 = 0
        for byte in bytes { mask |= bit(byte) }
        return mask
    }

    @inline(__always)
    static func bit(_ byte: UInt8) -> UInt64 {
        switch byte {
        case 0x61...0x7A: return 1 << UInt64(byte - 0x61)
        case 0x30...0x39: return 1 << UInt64(byte - 0x30 + 26)
        case space: return 0
        case 0x80...: return 1 << 63
        default: return 1 << UInt64(36 + Int(byte) % 27)
        }
    }

    @inline(__always)
    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    /// Letters, digits and every non-ASCII byte belong to words.
    @inline(__always)
    static func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= 0x61 && byte <= 0x7A) || isDigit(byte) || byte >= 0x80
    }

    /// A word starts at the beginning, after a separator (space _ - . and other
    /// punctuation), where letters turn to digits or back, and at a camelCase hump.
    /// Humps need the original case, so they are found in ASCII names only.
    @inline(__always)
    static func isBoundary(
        _ folded: UnsafeBufferPointer<UInt8>,
        _ original: UnsafeBufferPointer<UInt8>?,
        _ index: Int
    ) -> Bool {
        if index == 0 { return true }
        let previous = folded[index - 1]
        let current = folded[index]
        if !isWordByte(previous) { return true }
        if current < 0x80, previous < 0x80, isWordByte(current), isDigit(previous) != isDigit(current) { return true }
        if let original {
            let before = original[index - 1]
            let here = original[index]
            return before >= 0x61 && before <= 0x7A && here >= 0x41 && here <= 0x5A
        }
        return false
    }
}
