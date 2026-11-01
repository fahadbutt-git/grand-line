import Foundation

/// Put Back for items Finder (or another app asking Finder) moved to the
/// Trash: Finder keeps where each came from in the Trash folder's .DS_Store,
/// as two records per item, "ptbL" (the folder, relative to the volume's
/// root, such as "Users/me/Documents/") and "ptbN" (the original name).
///
/// The .DS_Store is a "Bud1" buddy-allocator file holding one B-tree, "DSDB".
/// This reads it and nothing else: a damaged or unknown file gives no records,
/// never a crash, and nothing is ever written to it.
public enum FinderPutBack {
    public struct Record: Equatable, Sendable {
        /// The original folder, relative to the volume root.
        public let folder: String
        public let name: String
    }

    /// The Trash item's name to where it came from, from a .DS_Store's bytes.
    public static func records(in data: Data) -> [String: Record] {
        guard let store = Store(Array(data)), let all = store.records() else { return [:] }
        var folders: [String: String] = [:]
        var names: [String: String] = [:]
        for record in all {
            switch record.code {
            case "ptbL": folders[record.file] = record.text
            case "ptbN": names[record.file] = record.text
            default: break
            }
        }
        var result: [String: Record] = [:]
        for (file, folder) in folders {
            result[file] = Record(folder: folder, name: names[file] ?? file)
        }
        return result
    }

    /// The items in `trash` (a Trash folder) that Finder can put back, with
    /// their original places. `volumeRoot` is the root of the volume the
    /// Trash belongs to ("/" for ~/.Trash).
    public static func originals(trash: URL, volumeRoot: URL = URL(fileURLWithPath: "/", isDirectory: true)) -> [String: URL] {
        guard let data = try? Data(contentsOf: trash.appendingPathComponent(".DS_Store")) else { return [:] }
        var result: [String: URL] = [:]
        for (file, record) in records(in: data) {
            let folder = record.folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let base = folder.isEmpty ? volumeRoot : volumeRoot.appendingPathComponent(folder, isDirectory: true)
            result[trash.appendingPathComponent(file).standardizedFileURL.path] = base.appendingPathComponent(record.name)
        }
        return result
    }

    struct Entry {
        let file: String
        let code: String
        /// A "ustr" record's text; nil for other types.
        let text: String?
    }

    /// The parts of the format Put Back needs, with every offset checked.
    struct Store {
        let bytes: [UInt8]
        /// Block number to its offset and size in `bytes`.
        let blocks: [(offset: Int, size: Int)]
        let directory: [String: Int]

        init?(_ bytes: [UInt8]) {
            self.bytes = bytes
            // 00 00 00 01, then "Bud1"; every offset after that counts from byte 4.
            guard bytes.count >= 36, Self.u32(bytes, 0) == 1, Array(bytes[4..<8]) == Array("Bud1".utf8),
                  let rootOffset = Self.u32(bytes, 8).map(Int.init), let rootSize = Self.u32(bytes, 12).map(Int.init) else { return nil }
            let root = rootOffset + 4
            guard root >= 4, rootSize > 8, root + rootSize <= bytes.count, let count = Self.u32(bytes, root).map(Int.init),
                  count < 1 << 20 else { return nil }
            var blocks: [(offset: Int, size: Int)] = []
            for i in 0..<count {
                guard let address = Self.u32(bytes, root + 8 + 4 * i) else { return nil }
                let offset = Int(address & ~0x1f) + 4
                let size = 1 << Int(address & 0x1f)
                blocks.append((offset: offset, size: size))
            }
            // The address table is padded to a multiple of 256 entries.
            var position = root + 8 + 4 * ((count + 255) / 256 * 256)
            guard let entries = Self.u32(bytes, position).map(Int.init), entries < 1 << 16 else { return nil }
            position += 4
            var directory: [String: Int] = [:]
            for _ in 0..<entries {
                guard position < bytes.count else { return nil }
                let length = Int(bytes[position])
                guard position + 1 + length + 4 <= bytes.count else { return nil }
                let name = String(decoding: bytes[(position + 1)..<(position + 1 + length)], as: UTF8.self)
                guard let block = Self.u32(bytes, position + 1 + length).map(Int.init) else { return nil }
                directory[name] = block
                position += 1 + length + 4
            }
            self.blocks = blocks
            self.directory = directory
        }

        static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
        }

        func u32(_ at: Int) -> UInt32? {
            Self.u32(bytes, at)
        }

        func block(_ number: Int) -> (offset: Int, size: Int)? {
            guard number >= 0, number < blocks.count else { return nil }
            let block = blocks[number]
            guard block.offset >= 4, block.offset < bytes.count else { return nil }
            return block
        }

        /// Every record in the B-tree, or nil when the file does not read as one.
        func records() -> [Entry]? {
            guard let db = directory["DSDB"], let header = block(db), let rootNode = u32(header.offset).map(Int.init) else { return nil }
            var found: [Entry] = []
            var visited = Set<Int>()
            guard walk(rootNode, depth: 0, visited: &visited, into: &found) else { return nil }
            return found
        }

        private func walk(_ node: Int, depth: Int, visited: inout Set<Int>, into found: inout [Entry]) -> Bool {
            guard depth < 32, visited.insert(node).inserted, let place = block(node),
                  let next = u32(place.offset).map(Int.init), let count = u32(place.offset + 4).map(Int.init),
                  count < 1 << 16 else { return false }
            var position = place.offset + 8
            for _ in 0..<count {
                if next != 0 {
                    guard let child = u32(position).map(Int.init) else { return false }
                    position += 4
                    guard walk(child, depth: depth + 1, visited: &visited, into: &found) else { return false }
                }
                guard let read = record(at: position) else { return false }
                found.append(read.entry)
                position = read.next
            }
            if next != 0 { return walk(next, depth: depth + 1, visited: &visited, into: &found) }
            return true
        }

        private func text(at position: Int, units: Int) -> String? {
            guard units >= 0, units < 1 << 16, position + 2 * units <= bytes.count else { return nil }
            var code: [UInt16] = []
            code.reserveCapacity(units)
            for i in 0..<units {
                code.append(UInt16(bytes[position + 2 * i]) << 8 | UInt16(bytes[position + 2 * i + 1]))
            }
            return String(decoding: code, as: UTF16.self)
        }

        private func record(at start: Int) -> (entry: Entry, next: Int)? {
            guard let length = u32(start).map(Int.init), let file = text(at: start + 4, units: length) else { return nil }
            var position = start + 4 + 2 * length
            guard position + 8 <= bytes.count else { return nil }
            let code = String(decoding: bytes[position..<(position + 4)], as: UTF8.self)
            let type = String(decoding: bytes[(position + 4)..<(position + 8)], as: UTF8.self)
            position += 8
            var value: String?
            switch type {
            case "bool": position += 1
            case "long", "shor", "type": position += 4
            case "comp", "dutc": position += 8
            case "blob":
                guard let size = u32(position).map(Int.init) else { return nil }
                position += 4 + size
            case "ustr":
                guard let units = u32(position).map(Int.init), let string = text(at: position + 4, units: units) else { return nil }
                value = string
                position += 4 + 2 * units
            default:
                return nil
            }
            guard position <= bytes.count else { return nil }
            return (entry: Entry(file: file, code: code, text: value), next: position)
        }
    }
}
