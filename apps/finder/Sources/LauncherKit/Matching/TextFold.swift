import Foundation

/// Text folded for matching: lowercase, without accents, as UTF-8 bytes, with
/// the word starts marked and a map back to UTF-16 offsets for highlights.
public struct FoldedText: Sendable, Hashable {
    public let bytes: [UInt8]
    /// For each byte, whether it starts a word.
    let starts: [Bool]
    /// For each byte, the UTF-16 range of the character it came from.
    let utf16Start: [Int32]
    let utf16End: [Int32]
    /// Bytes of the text without its extension ("Report.docx" → "report"), when it has one.
    let stemLength: Int?

    public init(_ text: String, stripsExtension: Bool = false) {
        var bytes: [UInt8] = []
        var starts: [Bool] = []
        var lo: [Int32] = []
        var hi: [Int32] = []
        bytes.reserveCapacity(text.utf8.count)
        var offset: Int32 = 0
        var previous: Character?
        for character in text {
            let width = Int32(character.utf16.count)
            let folded = TextFold.character(character)
            let boundary = TextFold.isBoundary(character, after: previous)
            for (k, byte) in folded.utf8.enumerated() {
                bytes.append(byte)
                starts.append(boundary && k == 0)
                lo.append(offset)
                hi.append(offset + width)
            }
            offset += width
            previous = character
        }
        self.bytes = bytes
        self.starts = starts
        self.utf16Start = lo
        self.utf16End = hi
        if stripsExtension, let dot = bytes.lastIndex(of: UInt8(ascii: ".")), dot > 0 {
            stemLength = dot
        } else {
            stemLength = nil
        }
    }

    public var isEmpty: Bool { bytes.isEmpty }

    /// The UTF-16 range of bytes `range` in the original text.
    func utf16Range(_ range: Range<Int>) -> Range<Int> {
        Int(utf16Start[range.lowerBound])..<Int(utf16End[range.upperBound - 1])
    }
}

public enum TextFold {
    /// Lowercase and without accents. ASCII takes a fast path.
    static func character(_ character: Character) -> String {
        if let ascii = character.asciiValue {
            return String(UnicodeScalar(ascii >= 65 && ascii <= 90 ? ascii + 32 : ascii))
        }
        return String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The whole string folded, words separated by single spaces.
    public static func simple(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
            .joined(separator: " ")
    }

    /// A word starts at the beginning, after a separator, at a camelCase hump and
    /// where letters turn into digits.
    static func isBoundary(_ character: Character, after previous: Character?) -> Bool {
        guard let previous else { return true }
        if isSeparator(previous) { return !isSeparator(character) }
        if character.isUppercase && previous.isLowercase { return true }
        if character.isNumber && previous.isLetter { return true }
        if character.isLetter && previous.isNumber { return true }
        return false
    }

    static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || "_-./()[]{}:,;&+|".contains(character)
    }
}
