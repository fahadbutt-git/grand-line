import Foundation
import IndexKit
@testable import FileKit

/// A temporary folder with its own pretend Trash, so tests never touch the real one.
final class Sandbox: Sendable {
    let root: URL
    let trashFolder: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("FileKitTests-\(UUID().uuidString)")
        let work = base.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: FolderWatcher.realPath(work.path), isDirectory: true)
        trashFolder = root.deletingLastPathComponent().appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// Moves into the pretend Trash, keeping both names like the real one.
    var trash: FileOperations.Trash {
        let folder = trashFolder
        return { url in
            let name = FileNaming.available(url.lastPathComponent, in: folder)
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func operations() -> FileOperations {
        FileOperations(trash: trash)
    }

    @discardableResult
    func file(_ relative: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relative).path)
    }

    func text(_ relative: String) -> String? {
        (try? Data(contentsOf: url(relative))).map { String(decoding: $0, as: UTF8.self) }
    }

    func names(_ relative: String = "") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(relative).path)) ?? []).sorted()
    }

    var trashed: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: trashFolder.path)) ?? []).sorted()
    }
}
