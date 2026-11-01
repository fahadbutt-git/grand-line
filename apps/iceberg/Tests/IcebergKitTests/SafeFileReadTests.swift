import XCTest
@testable import IcebergKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Widget files and iceberg.toml are read through SafeFileRead: a FIFO
/// must not block hot reload, and a link to /dev/zero must not fill memory.
final class SafeFileReadTests: XCTestCase {
    func testRegularFileAndSymlinkToOne() throws {
        let tmp = TempFolder()
        let real = tmp.write("real.toml", "title = \"R\"\ncommand = \"date\"")
        let link = tmp.url.appendingPathComponent("linked.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(try SafeFileRead.read(link, limit: 1024).get(), try Data(contentsOf: real))
        XCTAssertEqual(SafeFileRead.read(tmp.url.appendingPathComponent("none"), limit: 1024), .failure(.missing))
    }

    func testFIFODoesNotBlock() throws {
        let tmp = TempFolder()
        let fifo = tmp.url.appendingPathComponent("x.toml")
        guard mkfifo(fifo.path, 0o600) == 0 else { throw XCTSkip("mkfifo failed") }
        let started = Date()
        XCTAssertEqual(SafeFileRead.read(fifo, limit: 1024), .failure(.notAFile))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testDeviceAndOversizeAreRefused() throws {
        let tmp = TempFolder()
        let zero = tmp.url.appendingPathComponent("zero.toml")
        try FileManager.default.createSymbolicLink(at: zero, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
        XCTAssertEqual(SafeFileRead.read(zero, limit: 1024), .failure(.notAFile))
        let big = tmp.write("big.toml", String(repeating: "#", count: 2048))
        XCTAssertEqual(SafeFileRead.read(big, limit: 1024), .failure(.tooLarge))
    }

    func testLoaderSkipsSpecialFilesAndKeepsTheOthers() throws {
        let tmp = TempFolder()
        tmp.write("good.toml", "title = \"G\"\ncommand = \"date\"")
        guard mkfifo(tmp.url.appendingPathComponent("pipe.toml").path, 0o600) == 0 else { throw XCTSkip("mkfifo failed") }
        try FileManager.default.createSymbolicLink(at: tmp.url.appendingPathComponent("zero.toml"),
                                                   withDestinationURL: URL(fileURLWithPath: "/dev/zero"))
        let target = tmp.write("elsewhere/huge.txt", String(repeating: "#", count: WidgetLoader.maxFileSize + 10))
        try FileManager.default.createSymbolicLink(at: tmp.url.appendingPathComponent("huge.toml"), withDestinationURL: target)
        let started = Date()
        let r = WidgetLoader.load(from: tmp.url)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(r.widgets.map(\.id), ["good"])
        XCTAssertTrue(r.issues.contains { $0.file == "pipe.toml" && $0.message.contains("not a regular file") })
        XCTAssertTrue(r.issues.contains { $0.file == "zero.toml" && $0.message.contains("not a regular file") })
        XCTAssertTrue(r.issues.contains { $0.file == "huge.toml" && $0.message.contains("larger than") },
                      "a link no longer gets past the size check")
    }

    func testSettingsFIFOKeepsTheSettings() throws {
        let tmp = TempFolder()
        var before = IcebergSettings()
        before.menuBarIcon = false
        let fifo = tmp.url.appendingPathComponent("iceberg.toml")
        guard mkfifo(fifo.path, 0o600) == 0 else { throw XCTSkip("mkfifo failed") }
        let r = IcebergSettings.reload(from: fifo, previous: before)
        XCTAssertTrue(r.keptPrevious)
        XCTAssertEqual(r.settings, before)
    }
}
