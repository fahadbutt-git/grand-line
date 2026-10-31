import Foundation
import IndexKit
@testable import BrowserKit

/// A temporary folder for tests that touch the disk.
final class TempFolder {
    let root: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("BrowserKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: FolderWatcher.realPath(base.path), isDirectory: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
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
}

/// Rows without a disk.
func item(
    _ name: String, folder: Bool = false, size: Int64? = nil, modified: Date? = nil,
    kind: String = "", in parent: String = "/Users/me/Documents"
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: parent).appendingPathComponent(name, isDirectory: folder), name: name,
        isFolder: folder, size: folder ? nil : (size ?? 1), modified: modified, kind: kind.isEmpty ? (folder ? "Folder" : "Document") : kind
    )
}

let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
