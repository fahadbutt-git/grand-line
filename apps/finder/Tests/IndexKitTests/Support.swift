import Foundation
import XCTest
@testable import IndexKit

enum Fixture {
    static let root = "/Index"

    /// An index of made-up paths below `/Index`, without touching the disk.
    /// A path ending in "/" is a folder; parent folders are added as needed.
    static func storage(_ paths: [String]) -> IndexStorage {
        var storage = IndexStorage()
        var folders: [String: Int32] = ["": storage.addRoot(root)]
        for path in paths {
            let isFolder = path.hasSuffix("/")
            let parts = path.split(separator: "/").map(String.init)
            var parentKey = ""
            for (i, part) in parts.enumerated() {
                let key = parentKey.isEmpty ? part : parentKey + "/" + part
                let last = i == parts.count - 1
                if last && !isFolder {
                    storage.add(part, parent: folders[parentKey]!, isFolder: false)
                } else if folders[key] == nil {
                    folders[key] = storage.add(part, parent: folders[parentKey]!, isFolder: true)
                }
                parentKey = key
            }
        }
        return storage
    }

    static func index(_ paths: [String]) -> FileIndex {
        FileIndex(roots: [root], exclusions: .standard, storage: storage(paths), lastEventID: 0)
    }

    /// A new empty folder, as a real path.
    static func folder() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IndexKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return FolderWatcher.realPath(url.path)
    }

    static func make(_ relative: String, in folder: String) throws {
        let path = (folder as NSString).appendingPathComponent(relative)
        if relative.hasSuffix("/") {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: URL(fileURLWithPath: path))
        }
    }
}

func names(_ matches: [IndexMatch]) -> [String] {
    matches.map(\.name)
}

/// Word starts of a name, by the index's own rule, as byte offsets.
func wordStarts(_ name: String) -> [Int] {
    let folded = NameFold.fold(name)
    let original = Array(name.utf8)
    let ascii = NameFold.isASCII(name)
    return folded.withUnsafeBufferPointer { f in
        original.withUnsafeBufferPointer { o in
            (0..<f.count).filter { NameFold.isBoundary(f, ascii ? o : nil, $0) && NameFold.isWordByte(f[$0]) }
        }
    }
}

/// The tier a single name gets for a query, or nil.
func tier(_ query: String, _ name: String) -> MatchTier? {
    rank(query, name)?.tier
}

func rank(_ query: String, _ name: String) -> NameMatcher.Rank? {
    guard let parsed = SearchQuery(query) else { return nil }
    let folded = NameFold.fold(name)
    let original = Array(name.utf8)
    let ascii = NameFold.isASCII(name)
    var none: [Range<Int>]? = nil
    return parsed.bytes.withUnsafeBufferPointer { q in
        folded.withUnsafeBufferPointer { f in
            original.withUnsafeBufferPointer { o in
                NameMatcher.match(f, original: ascii ? o : nil, query: q, words: parsed.words, ranges: &none)
            }
        }
    }
}

/// The first batch from a stream, or nil after `seconds`.
func firstBatch(_ stream: AsyncStream<[FolderChange]>, within seconds: Double) async -> [FolderChange]? {
    await withTaskGroup(of: [FolderChange]?.self) { group in
        group.addTask {
            for await batch in stream { return batch }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
