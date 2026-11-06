import XCTest
@testable import LaunchKit

final class LaunchTests: XCTestCase {
    func testHotkeySetting() throws {
        let name = "LaunchKitTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(HotkeySetting.takesCommandSpace(defaults))
        defaults.set(true, forKey: HotkeySetting.key)
        XCTAssertTrue(HotkeySetting.takesCommandSpace(defaults))
        XCTAssertEqual(HotkeySetting.suiteName, "com.grandline.sight")
    }
}
