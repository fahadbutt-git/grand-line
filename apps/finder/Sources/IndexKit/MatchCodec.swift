import Foundation

/// Search results as one flat byte buffer, for the trip from the index service
/// to an app: no property lists or JSON, one allocation, a few hundred bytes for
/// a screenful.
///
/// Layout (little-endian): UInt32 count, then per match: UInt8 flags (bit 0
/// folder), UInt8 tier, UInt16 path length, the path's UTF-8, UInt16 name length,
/// the name's UTF-8, UInt16 highlight count, and two UInt32 per highlight.
public enum MatchCodec {
    public static func encode(_ matches: [IndexMatch]) -> Data {
        var out = SnapshotWriter()
        out.data.reserveCapacity(matches.count * 96 + 4)
        out.put(UInt32(matches.count).littleEndian)
        for match in matches {
            out.put(UInt8(match.isFolder ? 1 : 0))
            out.put(UInt8(match.tier.rawValue))
            putString(match.path, into: &out)
            putString(match.name, into: &out)
            out.put(UInt16(min(match.highlights.count, Int(UInt16.max))).littleEndian)
            for range in match.highlights.prefix(Int(UInt16.max)) {
                out.put(UInt32(clamping: range.lowerBound).littleEndian)
                out.put(UInt32(clamping: range.upperBound).littleEndian)
            }
        }
        return out.data
    }

    /// nil when the bytes are not a whole result list.
    public static func decode(_ data: Data) -> [IndexMatch]? {
        var input = SnapshotReader(data: data)
        do {
            let count = Int(UInt32(littleEndian: try input.take(UInt32.self)))
            guard count <= data.count else { return nil }
            var matches: [IndexMatch] = []
            matches.reserveCapacity(count)
            for _ in 0..<count {
                let flags = try input.take(UInt8.self)
                guard let tier = MatchTier(rawValue: Int(try input.take(UInt8.self))) else { return nil }
                let path = try string(from: &input)
                let name = try string(from: &input)
                let ranges = Int(UInt16(littleEndian: try input.take(UInt16.self)))
                var highlights: [Range<Int>] = []
                highlights.reserveCapacity(ranges)
                for _ in 0..<ranges {
                    let lower = Int(UInt32(littleEndian: try input.take(UInt32.self)))
                    let upper = Int(UInt32(littleEndian: try input.take(UInt32.self)))
                    guard lower <= upper else { return nil }
                    highlights.append(lower..<upper)
                }
                matches.append(IndexMatch(path: path, name: name, isFolder: flags & 1 != 0, tier: tier, highlights: highlights))
            }
            guard input.offset == data.count else { return nil }
            return matches
        } catch {
            return nil
        }
    }

    private static func putString(_ text: String, into out: inout SnapshotWriter) {
        let bytes = Array(text.utf8.prefix(Int(UInt16.max)))
        out.put(UInt16(bytes.count).littleEndian)
        out.data.append(contentsOf: bytes)
    }

    private static func string(from input: inout SnapshotReader) throws -> String {
        let length = Int(UInt16(littleEndian: try input.take(UInt16.self)))
        guard input.offset + length <= input.data.count else { throw IndexSnapshot.Failure.truncated }
        let start = input.offset
        let text = String(decoding: input.data[start..<(start + length)], as: UTF8.self)
        input.offset += length
        return text
    }
}
