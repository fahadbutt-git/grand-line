import Foundation

/// .DS_Store files and "._" AppleDouble files, which macOS leaves on shared drives.
public enum Clutter {
    public static func isClutter(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    /// The clutter in `folder`, and below it when `recursive`. Never looks
    /// inside packages (an app's "._" files are part of its signature) or on
    /// another volume mounted below the folder, and stops with a
    /// CancellationError when the task is cancelled. Call it off the main thread.
    public static func find(in folder: URL, recursive: Bool = true) throws -> [URL] {
        let fileManager = FileManager.default
        if !recursive {
            let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            return names.filter(isClutter).sorted().map { folder.appendingPathComponent($0) }
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        // Inside a package already: nothing in it is touched.
        if (try? folder.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return [] }
        let device = FileStamp.of(folder, followingLink: true)?.device
        guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                  options: [.skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        var seen = 0
        while let next = walker.nextObject() as? URL {
            seen += 1
            if seen & 255 == 0 { try Task.checkCancellation() }
            let values = try? next.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isSymbolicLink != true {
                if values?.isPackage == true || FileStamp.of(next)?.device != device { walker.skipDescendants() }
                continue
            }
            if isClutter(next.lastPathComponent) { found.append(next) }
        }
        try Task.checkCancellation()
        return found.sorted { $0.path < $1.path }
    }

    /// Moves the clutter to the Trash as one undoable operation. Returns the Trash locations.
    @discardableResult
    public static func clean(in folder: URL, recursive: Bool = true, using operations: FileOperations) async throws -> [URL] {
        let items = try find(in: folder, recursive: recursive)
        guard !items.isEmpty else { return [] }
        return try await operations.moveToTrash(items)
    }
}
