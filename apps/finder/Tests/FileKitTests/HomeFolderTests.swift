import XCTest
@testable import FileKit

/// The one home folder: a fixed home (the user journeys' fixture) wins over
/// the account's real one.
final class HomeFolderTests: XCTestCase {
    func testFixedHomeComesFirst() {
        let url = HomeFolder.url(environment: ["CFFIXED_USER_HOME": "/tmp/journeyhome", "HOME": "/Users/me"], fallback: { "/Users/me" })
        XCTAssertEqual(url.path, "/tmp/journeyhome")
    }

    func testWithoutAFixedHomeItIsTheAccountsHome() {
        XCTAssertEqual(HomeFolder.url(environment: [:], fallback: { "/Users/me" }).path, "/Users/me")
        XCTAssertEqual(HomeFolder.url(environment: ["CFFIXED_USER_HOME": ""], fallback: { "/Users/me" }).path, "/Users/me")
        XCTAssertEqual(HomeFolder.url(environment: ["CFFIXED_USER_HOME": "relative"], fallback: { "/Users/me" }).path, "/Users/me")
    }

    func testTheDefaultMatchesNSHomeDirectory() {
        XCTAssertEqual(HomeFolder.path, URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path)
    }
}
