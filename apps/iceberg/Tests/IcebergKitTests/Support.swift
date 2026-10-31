import Foundation
import XCTest

/// A fresh folder for one test, removed afterwards.
final class TempFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iceberg-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ name: String, _ text: String) -> URL {
        let file = url.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: file)
        return file
    }

    @discardableResult
    func write(_ name: String, data: Data) -> URL {
        let file = url.appendingPathComponent(name)
        try? data.write(to: file)
        return file
    }
}

/// The app's folder (apps/iceberg), found from this file's path.
let appFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // IcebergKitTests
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // iceberg

/// The package's root, for its real theme files.
let repoFolder = appFolder.deletingLastPathComponent().deletingLastPathComponent()

/// Collects results from commands finishing on other threads.
final class Collector<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Value] = [:]

    func set(_ key: String, _ value: Value) {
        lock.lock(); storage[key] = value; lock.unlock()
    }

    var values: [String: Value] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
