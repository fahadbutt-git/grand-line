import XCTest
@testable import LaunchKit

final class LaunchTests: XCTestCase {
    private func event(_ eventClass: UInt32, _ eventID: UInt32, _ urls: [URL]) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: eventClass, eventID: eventID, targetDescriptor: nil,
            returnID: -1, transactionID: 0
        )
        let list = NSAppleEventDescriptor.list()
        for url in urls {
            list.insert(NSAppleEventDescriptor(fileURL: url), at: list.numberOfItems + 1)
        }
        event.setParam(list, forKeyword: FileViewerRequest.directObject)
        return event
    }

    private let a = URL(fileURLWithPath: "/Users/me/Documents/a.pdf")
    private let b = URL(fileURLWithPath: "/Users/me/Documents/b.pdf")
    private let other = URL(fileURLWithPath: "/Users/me/Desktop/c.pdf")

    private func paths(_ request: FileViewerRequest?) -> (kind: String, paths: [String])? {
        switch request {
        case .open(let urls): return ("open", urls.map(\.path))
        case .reveal(let urls): return ("reveal", urls.map(\.path))
        case nil: return nil
        }
    }

    func testRevealEvent() {
        let request = FileViewerRequest.parse(event(0x6D69_7363, 0x6D76_6973, [a, b, other]))
        XCTAssertEqual(paths(request)?.kind, "reveal")
        XCTAssertEqual(paths(request)?.paths, [a.path, b.path, other.path])
        XCTAssertEqual(request?.target.folder.path, "/Users/me/Documents")
        XCTAssertEqual(request?.target.selection.map(\.path), [a.path, b.path])
    }

    func testOpenEvent() {
        let folder = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)
        let request = FileViewerRequest.parse(event(0x6165_7674, 0x6F64_6F63, [folder]))
        XCTAssertEqual(paths(request)?.kind, "open")
        XCTAssertEqual(paths(request)?.paths, [folder.path])
        XCTAssertEqual(request?.target.folder.path, folder.path)
        XCTAssertEqual(request?.target.selection, [])
    }

    func testOtherEventsAndEmptyEvents() {
        XCTAssertNil(FileViewerRequest.parse(event(0x6165_7674, 0x7175_6974, [a]))) // 'quit'
        XCTAssertNil(FileViewerRequest.parse(event(0x6D69_7363, 0x6D76_6973, [])))
        XCTAssertEqual(FileViewerRequest.handledEvents.count, 2)
    }

    func testSingleItemDescriptor() {
        XCTAssertEqual(FileViewerRequest.fileURLs(in: NSAppleEventDescriptor(fileURL: a)).map(\.path), [a.path])
    }

    func testHotkeySetting() throws {
        let name = "LaunchKitTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(HotkeySetting.takesCommandSpace(defaults))
        defaults.set(true, forKey: HotkeySetting.key)
        XCTAssertTrue(HotkeySetting.takesCommandSpace(defaults))
        XCTAssertEqual(HotkeySetting.suiteName, "com.grandline.byakugan")
    }
}
