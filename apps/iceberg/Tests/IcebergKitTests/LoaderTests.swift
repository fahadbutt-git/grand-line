import XCTest
@testable import IcebergKit

final class LoaderTests: XCTestCase {
    func testMissingFolderIsEmpty() {
        let r = WidgetLoader.load(from: URL(fileURLWithPath: "/nonexistent/iceberg/widgets"))
        XCTAssertTrue(r.widgets.isEmpty)
        XCTAssertTrue(r.issues.isEmpty)
    }

    func testOrderAndFiltering() {
        let tmp = TempFolder()
        tmp.write("b.toml", "title = \"B\"\ncommand = \"echo b\"")
        tmp.write("a.toml", "title = \"A\"\ncommand = \"echo a\"")
        tmp.write("z.json", #"{"title": "Z", "command": "echo z", "order": -5}"#)
        tmp.write("off.toml", "title = \"Off\"\ncommand = \"echo off\"\nenabled = false")
        tmp.write("notes.txt", "ignored")
        tmp.write(".hidden.toml", "title = \"H\"\ncommand = \"echo h\"")
        tmp.write("weather.sh", "#!/bin/sh\necho hi")
        let r = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(r.widgets.map(\.id), ["z", "a", "b"])
        XCTAssertEqual(r.issues, [])
        XCTAssertEqual(r.widgets.first?.file?.lastPathComponent, "z.json")
    }

    func testDuplicateIDsAreReported() {
        let tmp = TempFolder()
        tmp.write("clock.json", #"{"title": "J", "command": "date"}"#)
        tmp.write("clock.toml", "title = \"T\"\ncommand = \"date\"")
        let r = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(r.widgets.count, 1)
        XCTAssertTrue(r.issues.contains { $0.message.contains("already defines") })
    }

    func testOneBrokenFileDoesNotStopTheRest() {
        let tmp = TempFolder()
        tmp.write("good.toml", "title = \"Good\"\ncommand = \"echo ok\"")
        tmp.write("bad.toml", "title = \"Bad\ncommand = ")
        let r = WidgetLoader.load(from: tmp.url)
        XCTAssertEqual(r.widgets.map(\.id), ["good"])
        XCTAssertEqual(r.issues.filter { $0.severity == .error }.map(\.file), ["bad.toml"])
    }
}
