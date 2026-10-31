import Foundation

/// The index on disk: the arrays as raw bytes, so loading is a few copies and the
/// search window has results before the first rescan finishes.
struct IndexSnapshot {
    static let magic: UInt32 = 0x474C_4958 // "GLIX"
    /// Version 2 adds whether the walk had finished; version 3 adds the volume
    /// UUID of each root, so a restored or reformatted disk is noticed, and names
    /// are folded after composing them (NFC). Versions 1 and 2 still load: their
    /// non-ASCII names are folded again on load, so nothing is rebuilt.
    static let version: UInt32 = 3

    var roots: [String]
    var storage: IndexStorage
    var usage: [String: Usage]
    var lastEventID: UInt64
    /// False for a snapshot saved part way through a first build.
    var complete: Bool
    /// The FSEvents volume UUID of each root's disk when the snapshot was saved.
    /// Empty for snapshots from before version 3.
    var volumes: [String: String] = [:]

    enum Failure: Error, Equatable {
        case notAnIndex
        case wrongVersion(UInt32)
        case truncated
    }

    func encoded() throws -> Data {
        var out = SnapshotWriter()
        out.put(Self.magic)
        out.put(Self.version)
        out.put(lastEventID)
        out.put(UInt8(complete ? 1 : 0))
        out.put(UInt64(roots.count))
        for root in roots { out.put(Array(root.utf8)) }
        out.put(storage.names)
        out.put(storage.folded)
        out.put(storage.nameStart)
        out.put(storage.nameLength)
        out.put(storage.foldStart)
        out.put(storage.foldLength)
        out.put(storage.parent)
        out.put(storage.depth)
        out.put(storage.flags)
        out.put(storage.mask)
        out.put(UInt64(storage.roots.count))
        for (index, path) in storage.roots.sorted(by: { $0.key < $1.key }) {
            out.put(index)
            out.put(Array(path.utf8))
        }
        out.put(Array(try JSONEncoder().encode(usage)))
        out.put(Array(try JSONEncoder().encode(volumes)))
        return out.data
    }

    init(
        roots: [String], storage: IndexStorage, usage: [String: Usage], lastEventID: UInt64,
        complete: Bool = true, volumes: [String: String] = [:]
    ) {
        self.roots = roots
        self.storage = storage
        self.usage = usage
        self.lastEventID = lastEventID
        self.complete = complete
        self.volumes = volumes
    }

    /// What a snapshot file says about itself, read without decoding the arrays.
    struct Header: Equatable {
        var version: UInt32
        var lastEventID: UInt64
        var complete: Bool
        var roots: [String]
    }

    static func header(of data: Data) throws -> Header {
        var input = SnapshotReader(data: data)
        guard try input.take(UInt32.self) == magic else { throw Failure.notAnIndex }
        let version = try input.take(UInt32.self)
        guard (1...Self.version).contains(version) else { throw Failure.wrongVersion(version) }
        let eventID = try input.take(UInt64.self)
        let complete = try version == 1 || input.take(UInt8.self) != 0
        var roots: [String] = []
        let rootCount = try input.count()
        for _ in 0..<rootCount { roots.append(try input.string()) }
        return Header(version: version, lastEventID: eventID, complete: complete, roots: roots)
    }

    init(decoding data: Data) throws {
        var input = SnapshotReader(data: data)
        guard try input.take(UInt32.self) == Self.magic else { throw Failure.notAnIndex }
        let version = try input.take(UInt32.self)
        guard (1...Self.version).contains(version) else { throw Failure.wrongVersion(version) }
        let eventID = try input.take(UInt64.self)
        let complete = try version == 1 || input.take(UInt8.self) != 0
        var rootList: [String] = []
        let rootCount = try input.count()
        for _ in 0..<rootCount {
            rootList.append(try input.string())
        }
        var storage = IndexStorage()
        storage.names = try input.array(UInt8.self)
        storage.folded = try input.array(UInt8.self)
        storage.nameStart = try input.array(UInt32.self)
        storage.nameLength = try input.array(UInt16.self)
        storage.foldStart = try input.array(UInt32.self)
        storage.foldLength = try input.array(UInt16.self)
        storage.parent = try input.array(Int32.self)
        storage.depth = try input.array(UInt16.self)
        storage.flags = try input.array(UInt8.self)
        storage.mask = try input.array(UInt64.self)
        let count = storage.parent.count
        let lengths = [storage.nameStart.count, storage.nameLength.count, storage.foldStart.count,
                       storage.foldLength.count, storage.depth.count, storage.flags.count, storage.mask.count]
        guard lengths.allSatisfy({ $0 == count }) else { throw Failure.truncated }
        for i in 0..<count {
            let nameEnd = Int(storage.nameStart[i]) + Int(storage.nameLength[i])
            let foldEnd = Int(storage.foldStart[i]) + Int(storage.foldLength[i])
            let parent = Int(storage.parent[i])
            guard nameEnd <= storage.names.count, foldEnd <= storage.folded.count, parent < i else {
                throw Failure.truncated
            }
        }
        storage.boost = [Float](repeating: 0, count: count)
        let storedRoots = try input.count()
        for _ in 0..<storedRoots {
            let index = try input.take(Int32.self)
            storage.roots[index] = try input.string()
        }
        var removed = 0
        for flag in storage.flags where flag & IndexStorage.removedFlag != 0 { removed += 1 }
        storage.removedCount = removed
        let usageBytes = try input.array(UInt8.self)
        let usage = try JSONDecoder().decode([String: Usage].self, from: Data(usageBytes))
        var volumes: [String: String] = [:]
        if version >= 3 {
            volumes = try JSONDecoder().decode([String: String].self, from: Data(try input.array(UInt8.self)))
        } else {
            storage.refold()
        }
        self.init(roots: rootList, storage: storage, usage: usage, lastEventID: eventID, complete: complete, volumes: volumes)
    }
}

struct SnapshotWriter {
    var data = Data()

    mutating func put<T: BitwiseCopyable>(_ value: T) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    mutating func put<T: BitwiseCopyable>(_ values: [T]) {
        put(UInt64(values.count))
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
}

struct SnapshotReader {
    let data: Data
    var offset = 0

    init(data: Data) {
        self.data = Data(data)
    }

    mutating func take<T: BitwiseCopyable>(_ type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { throw IndexSnapshot.Failure.truncated }
        let start = offset
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: start, as: T.self) }
        offset += size
        return value
    }

    mutating func count() throws -> Int {
        let value = try take(UInt64.self)
        guard value <= UInt64(data.count) else { throw IndexSnapshot.Failure.truncated }
        return Int(value)
    }

    mutating func array<T: BitwiseCopyable>(_ type: T.Type) throws -> [T] {
        let count = try count()
        let bytes = count * MemoryLayout<T>.stride
        guard offset + bytes <= data.count else { throw IndexSnapshot.Failure.truncated }
        let start = offset
        let source = data
        let result = [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            if bytes > 0 {
                source.withUnsafeBytes { raw in
                    UnsafeMutableRawBufferPointer(buffer).copyMemory(
                        from: UnsafeRawBufferPointer(rebasing: raw[start..<(start + bytes)])
                    )
                }
            }
            initialized = count
        }
        offset += bytes
        return result
    }

    mutating func string() throws -> String {
        let bytes = try array(UInt8.self)
        return String(decoding: bytes, as: UTF8.self)
    }
}
