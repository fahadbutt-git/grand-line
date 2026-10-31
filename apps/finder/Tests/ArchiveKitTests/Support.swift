import Foundation
import XCTest

/// A temporary folder for making and opening archives.
final class Workspace {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    @discardableResult
    func file(_ relative: String, _ text: String) throws -> URL {
        let url = self.url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Runs a tool inside `folder` (relative to the workspace).
    func run(_ tool: String, _ arguments: [String], in folder: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = url(folder)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(tool) \(arguments)")
    }

    /// A zip of `folder`'s contents, made with /usr/bin/zip.
    func zip(_ folder: String, to name: String) throws -> URL {
        try run("/usr/bin/zip", ["-qr", url(name).path, "."], in: folder)
        return url(name)
    }

    /// A tar of `folder`'s contents, made with bsdtar, compressed by the name's suffix,
    /// without the "._" entries macOS adds for extended attributes.
    func tar(_ folder: String, to name: String) throws -> URL {
        try run("/usr/bin/bsdtar", ["--no-mac-metadata", "-acf", url(name).path, "."], in: folder)
        return url(name)
    }

    /// A tar written by hand, so it can hold names bsdtar would never write.
    func handmadeTar(_ files: [(name: String, text: String)], to name: String) throws -> URL {
        var data = Data()
        for file in files {
            let body = Array(file.text.utf8)
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int) {
                for (i, byte) in text.utf8.enumerated() { header[offset + i] = byte }
            }
            put(file.name, at: 0)
            put("0000644", at: 100)
            put("0000000", at: 108)
            put("0000000", at: 116)
            put(String(format: "%011o", body.count), at: 124)
            put(String(format: "%011o", 1_700_000_000), at: 136)
            put("        ", at: 148)
            put("0", at: 156)
            put("ustar", at: 257)
            put("00", at: 263)
            let sum = header.reduce(0) { $0 + Int($1) }
            put(String(format: "%06o", sum), at: 148)
            header[154] = 0
            header[155] = 0x20
            data.append(contentsOf: header)
            data.append(contentsOf: body)
            data.append(contentsOf: [UInt8](repeating: 0, count: (512 - body.count % 512) % 512))
        }
        data.append(contentsOf: [UInt8](repeating: 0, count: 1024))
        let url = self.url(name)
        try data.write(to: url)
        return url
    }
}
