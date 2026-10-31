import Foundation

/// The index as parallel arrays, one slot per file or folder, in the manner of
/// FSearch: an entry keeps its name and its parent, and paths are rebuilt on demand.
/// A parent always comes before its children. Removed entries are flagged and
/// dropped by `compacted()`.
struct IndexStorage: Sendable {
    static let folderFlag: UInt8 = 1
    static let removedFlag: UInt8 = 2
    static let asciiFlag: UInt8 = 4
    static let rootFlag: UInt8 = 8

    var names: [UInt8] = []
    var folded: [UInt8] = []
    var nameStart: [UInt32] = []
    var nameLength: [UInt16] = []
    var foldStart: [UInt32] = []
    var foldLength: [UInt16] = []
    var parent: [Int32] = []
    var depth: [UInt16] = []
    var flags: [UInt8] = []
    var mask: [UInt64] = []
    /// Frequency and recency of use, from `Usage`.
    var boost: [Float] = []
    /// Root entries and their absolute paths.
    var roots: [Int32: String] = [:]
    var removedCount = 0

    var count: Int { parent.count }
    var liveCount: Int { count - removedCount }

    @discardableResult
    mutating func add(_ name: String, parent: Int32, isFolder: Bool) -> Int32 {
        let index = Int32(count)
        let fold = NameFold.fold(name)
        let utf8Count = name.utf8.count
        nameStart.append(UInt32(names.count))
        nameLength.append(UInt16(min(utf8Count, Int(UInt16.max))))
        names.append(contentsOf: name.utf8)
        foldStart.append(UInt32(folded.count))
        foldLength.append(UInt16(min(fold.count, Int(UInt16.max))))
        folded.append(contentsOf: fold)
        self.parent.append(parent)
        depth.append(parent < 0 ? 0 : depth[Int(parent)] &+ 1)
        var flag: UInt8 = 0
        if isFolder { flag |= Self.folderFlag }
        if NameFold.isASCII(name) { flag |= Self.asciiFlag }
        flags.append(flag)
        mask.append(NameFold.mask(fold))
        boost.append(0)
        return index
    }

    mutating func addRoot(_ path: String) -> Int32 {
        let name = path == "/" ? "/" : (path as NSString).lastPathComponent
        let index = add(name, parent: -1, isFolder: true)
        flags[Int(index)] |= Self.rootFlag
        roots[index] = path
        return index
    }

    func isLive(_ i: Int) -> Bool { flags[i] & Self.removedFlag == 0 }
    func isFolder(_ i: Int) -> Bool { flags[i] & Self.folderFlag != 0 }
    func isRoot(_ i: Int) -> Bool { flags[i] & Self.rootFlag != 0 }

    func name(_ i: Int) -> String {
        let start = Int(nameStart[i])
        return String(decoding: names[start..<(start + Int(nameLength[i]))], as: UTF8.self)
    }

    func path(_ i: Int) -> String {
        var parts: [String] = []
        var j = i
        while j >= 0, !isRoot(j) {
            parts.append(name(j))
            j = Int(parent[j])
        }
        let base = j >= 0 ? roots[Int32(j)] ?? "" : ""
        return Self.join(base, parts.reversed().joined(separator: "/"))
    }

    static func join(_ base: String, _ rest: String) -> String {
        if rest.isEmpty { return base }
        return base.hasSuffix("/") ? base + rest : base + "/" + rest
    }

    /// Live children of a folder by name. A full pass, used only for rescans.
    func children(of folder: Int32) -> [String: Int32] {
        var result: [String: Int32] = [:]
        var i = Int(folder) + 1
        while i < count {
            if parent[i] == folder, isLive(i) { result[name(i)] = Int32(i) }
            i += 1
        }
        return result
    }

    /// Flags the entry and everything below it as removed. Returns the folders removed.
    @discardableResult
    mutating func remove(_ index: Int32) -> [Int32] {
        let start = Int(index)
        guard isLive(start) else { return [] }
        flags[start] |= Self.removedFlag
        removedCount += 1
        guard isFolder(start) else { return [] }
        var folders: [Int32] = [index]
        var gone = [Bool](repeating: false, count: count - start)
        gone[0] = true
        var i = start + 1
        while i < count {
            let p = Int(parent[i])
            if p >= start, gone[p - start], isLive(i) {
                gone[i - start] = true
                flags[i] |= Self.removedFlag
                removedCount += 1
                if isFolder(i) { folders.append(Int32(i)) }
            }
            i += 1
        }
        return folders
    }

    /// Removes everything below a folder, keeping the folder.
    @discardableResult
    mutating func removeContents(of folder: Int32) -> [Int32] {
        var removed: [Int32] = []
        for (_, child) in children(of: folder) { removed += remove(child) }
        return removed
    }

    /// A copy without removed entries, in the same order.
    func compacted() -> IndexStorage {
        var out = IndexStorage()
        var map = [Int32](repeating: -1, count: count)
        for i in 0..<count where isLive(i) {
            let p = parent[i]
            let newParent = p < 0 ? -1 : map[Int(p)]
            if p >= 0, newParent < 0 { continue }
            map[i] = Int32(out.count)
            let ns = Int(nameStart[i])
            out.nameStart.append(UInt32(out.names.count))
            out.nameLength.append(nameLength[i])
            out.names.append(contentsOf: names[ns..<(ns + Int(nameLength[i]))])
            let fs = Int(foldStart[i])
            out.foldStart.append(UInt32(out.folded.count))
            out.foldLength.append(foldLength[i])
            out.folded.append(contentsOf: folded[fs..<(fs + Int(foldLength[i]))])
            out.parent.append(newParent)
            out.depth.append(depth[i])
            out.flags.append(flags[i])
            out.mask.append(mask[i])
            out.boost.append(boost[i])
        }
        for (index, path) in roots where map[Int(index)] >= 0 {
            out.roots[map[Int(index)]] = path
        }
        return out
    }

    /// Every live folder by absolute path.
    func folderPaths() -> [String: Int32] {
        var pathOf: [Int32: String] = [:]
        var result: [String: Int32] = [:]
        for i in 0..<count where isLive(i) && isFolder(i) {
            let path: String
            if isRoot(i) {
                path = roots[Int32(i)] ?? ""
            } else if let parentPath = pathOf[parent[i]] {
                path = Self.join(parentPath, name(i))
            } else {
                continue
            }
            pathOf[Int32(i)] = path
            result[path] = Int32(i)
        }
        return result
    }
}
