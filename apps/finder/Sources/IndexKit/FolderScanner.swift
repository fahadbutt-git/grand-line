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
        guard let dir = opendir(path) else { return nil }
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

    static func build(roots: [String], exclusions: IndexExclusions) -> BuiltIndex {
        var storage = IndexStorage()
        var folders: [String: Int32] = [:]
        for root in roots where isDirectory(root) {
            let index = storage.addRoot(root)
            folders[root] = index
            for (path, folder) in addContents(of: root, at: index, to: &storage, exclusions: exclusions) {
                folders[path] = folder
            }
        }
        return BuiltIndex(storage: storage, folders: folders)
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
}
