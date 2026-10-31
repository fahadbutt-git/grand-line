import Foundation

/// .DS_Store files and "._" AppleDouble files, which macOS leaves on shared drives.
public enum Clutter {
    public static func isClutter(_ name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    public static func find(in folder: URL, recursive: Bool = true) -> [URL] {
        let fileManager = FileManager.default
        let names: [String]
        if recursive {
            names = (fileManager.enumerator(atPath: folder.path)?.allObjects as? [String]) ?? []
        } else {
            names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        }
        return names
            .filter { isClutter(($0 as NSString).lastPathComponent) }
            .sorted()
            .map { folder.appendingPathComponent($0) }
    }

    /// Moves the clutter to the Trash as one undoable operation. Returns the Trash locations.
    @discardableResult
    public static func clean(in folder: URL, recursive: Bool = true, using operations: FileOperations) async throws -> [URL] {
        let items = find(in: folder, recursive: recursive)
        guard !items.isEmpty else { return [] }
        return try await operations.moveToTrash(items)
    }
}
