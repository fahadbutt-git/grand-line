import Foundation

/// Reads folders with readdir, which gives names and types in one call, the way
/// Nimble Commander lists folders quickly. Children are sorted by name.
enum FolderScanner {
    struct Child: Equatable {
        let name: String
        /// True for folders the index goes into. Packages and links are items.
        let isFolder: Bool
    }

    /// nil when the folder cannot be read (gone, or no permission).
    static func list(_ path: String, exclusions: IndexExclusions) -> [Child]? {
        var denied = false
        return list(path, exclusions: exclusions, denied: &denied)
    }

    /// Sets `denied` when the folder exists but macOS would not let us read it,
    /// as with Desktop, Documents or Downloads before the app is allowed in.
    static func list(_ path: String, exclusions: IndexExclusions, denied: inout Bool) -> [Child]? {
        guard let dir = opendir(path) else {
            let code = errno
            denied = code == EPERM || code == EACCES
            return nil
        }
        defer { closedir(dir) }
        var children: [Child] = []
        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { tuple in
                tuple.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tuple.pointee)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." || exclusions.skips(name) { continue }
            let full = IndexStorage.join(path, name)
            if !exclusions.paths.isEmpty, exclusions.skips(path: full) { continue }
            var isFolder: Bool
            switch Int32(entry.pointee.d_type) {
            case DT_DIR: isFolder = true
            case DT_UNKNOWN: isFolder = isDirectory(full)
            default: isFolder = false
            }
            if isFolder, exclusions.isPackage(name) { isFolder = false }
            children.append(Child(name: name, isFolder: isFolder))
        }
        children.sort { $0.name < $1.name }
        return children
    }

    /// Adds one child of `parent` and, for a folder, everything below it.
    /// Returns the folders added, with their paths.
    static func add(
        _ child: Child,
        in parentPath: String,
        at parent: Int32,
        to storage: inout IndexStorage,
        exclusions: IndexExclusions
    ) -> [(String, Int32)] {
        let index = storage.add(child.name, parent: parent, isFolder: child.isFolder)
        guard child.isFolder else { return [] }
        let path = IndexStorage.join(parentPath, child.name)
        return [(path, index)] + addContents(of: path, at: index, to: &storage, exclusions: exclusions)
    }

    /// Adds everything below a folder already in the index.
    static func addContents(
        of path: String,
        at index: Int32,
        to storage: inout IndexStorage,
        exclusions: IndexExclusions
    ) -> [(String, Int32)] {
        var added: [(String, Int32)] = []
        var pending: [(String, Int32)] = [(path, index)]
        while let next = pending.popLast() {
            let (folder, folderIndex) = next
            guard let children = list(folder, exclusions: exclusions) else { continue }
            for child in children {
                let childIndex = storage.add(child.name, parent: folderIndex, isFolder: child.isFolder)
                if child.isFolder {
                    let childPath = IndexStorage.join(folder, child.name)
                    added.append((childPath, childIndex))
                    pending.append((childPath, childIndex))
                }
            }
        }
        return added
    }

    /// Walks every root. Folders in `order.first` are walked before the rest and
    /// folders in `order.last` after everything else. After `interval` seconds the
    /// index so far goes to `publish`, so it can be searched while the walk goes on,
    /// then again at doubling gaps up to 4 seconds (each publish costs a copy).
    static func build(
        roots: [String],
        exclusions: IndexExclusions,
        order: ScanOrder = .none,
        interval: TimeInterval = .infinity,
        publish: (BuiltIndex) -> Void = { _ in }
    ) -> BuiltIndex {
        var storage = IndexStorage()
        var folders: [String: Int32] = [:]
        var unreadable: [String] = []
        var deferred: [(String, Int32)] = []
        var rank: [String: Int] = [:]
        for (i, path) in order.first.enumerated() where rank[path] == nil { rank[path] = i }
        let last = Set(order.last)
        var step = 0
        var published = ProcessInfo.processInfo.systemUptime
        var gap = interval

        func walk(_ start: [(String, Int32)]) {
            var pending = start
            var next: [(path: String, index: Int32, rank: Int)] = []
            while let item = pending.popLast() {
                let (folder, folderIndex) = item
                var denied = false
                guard let children = list(folder, exclusions: exclusions, denied: &denied) else {
                    if denied { unreadable.append(folder) }
                    continue
                }
                next.removeAll(keepingCapacity: true)
                for child in children {
                    let childIndex = storage.add(child.name, parent: folderIndex, isFolder: child.isFolder)
                    guard child.isFolder else { continue }
                    let path = IndexStorage.join(folder, child.name)
                    folders[path] = childIndex
                    if last.contains(path) {
                        deferred.append((path, childIndex))
                    } else {
                        next.append((path, childIndex, rank[path] ?? Int.max))
                    }
                }
                // The stack pops from the end, so the folders wanted first go on last.
                for item in next where item.rank == Int.max { pending.append((item.path, item.index)) }
                for item in next.filter({ $0.rank != Int.max }).sorted(by: { $0.rank > $1.rank }) {
                    pending.append((item.path, item.index))
                }
                let now = ProcessInfo.processInfo.systemUptime
                if now - published >= gap {
                    published = now
                    gap = min(gap * 2, max(interval, 4))
                    step += 1
                    publish(BuiltIndex(storage: storage, folders: folders, unreadable: unreadable, step: step, complete: false))
                }
            }
        }

        var starts: [(String, Int32)] = []
        for root in roots where isDirectory(root) {
            let index = storage.addRoot(root)
            folders[root] = index
            starts.append((root, index))
        }
        walk(starts.reversed())
        let lastRank = Dictionary(order.last.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        deferred.sort { (lastRank[$0.0] ?? Int.max) < (lastRank[$1.0] ?? Int.max) }
        while !deferred.isEmpty {
            walk([deferred.removeFirst()])
        }
        return BuiltIndex(storage: storage, folders: folders, unreadable: unreadable, step: step + 1, complete: true)
    }

    /// Does not follow symbolic links.
    static func isDirectory(_ path: String) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        return type == .typeDirectory
    }
}

struct BuiltIndex: Sendable {
    let storage: IndexStorage
    let folders: [String: Int32]
    /// Folders the walk was not allowed to read.
    var unreadable: [String] = []
    /// Counts up with each publish; the finished walk has the highest.
    var step = 0
    var complete = true
}
