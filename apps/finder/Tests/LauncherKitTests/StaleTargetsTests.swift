import XCTest
@testable import LauncherKit

final class StaleTargetsTests: XCTestCase {
    private func row(_ id: String, _ command: ActionCommand) -> LaunchResult {
        LaunchResult(id: id, title: id, icon: .symbol("gear"), section: .grandLine,
                     actions: [LaunchAction("Run", symbol: "play", command)])
    }

    func testTargetsOfTheFirstAction() {
        XCTAssertEqual(StaleTargets.targets(of: .shell("open 'app-settings://settings'")), [.scheme("app-settings")])
        XCTAssertEqual(StaleTargets.targets(of: .shell("open -g -j \"iceberg://toggle\"")), [.scheme("iceberg")])
        XCTAssertEqual(StaleTargets.targets(of: .shell("open -b com.example.app")), [.bundleID("com.example.app")])
        XCTAssertEqual(StaleTargets.targets(of: .open("sight://settings")), [.scheme("sight")])
        XCTAssertEqual(StaleTargets.targets(of: .openURL("https://example.com", bundleID: "com.example.browser")),
                       [.bundleID("com.example.browser")])
        XCTAssertEqual(StaleTargets.targets(of: .run("/usr/bin/open", arguments: ["myapp://x"])), [.scheme("myapp")])
        XCTAssertEqual(StaleTargets.targets(of: .run("/Users/me/.grand-line/bin/old", arguments: ["pick"])),
                       [.executable("/Users/me/.grand-line/bin/old")])
    }

    func testWebPagesFilesAndOtherLinesNameNothing() {
        XCTAssertEqual(StaleTargets.targets(of: .open("https://example.com")), [])
        XCTAssertEqual(StaleTargets.targets(of: .open("/Users/me/Documents")), [])
        XCTAssertEqual(StaleTargets.targets(of: .shell("open 'x-apple.systempreferences:com.apple.Displays-Settings.extension'")), [])
        XCTAssertEqual(StaleTargets.targets(of: .shell("echo 'gone://x'")), [])
        XCTAssertEqual(StaleTargets.targets(of: .shell("open -a TextEdit \"$HOME/notes.txt\"")), [])
        XCTAssertEqual(StaleTargets.targets(of: .shell("open 'a://b'; open 'c://d'")), [.scheme("a")])
        XCTAssertEqual(StaleTargets.targets(of: .copyText("gone://x")), [])
    }

    func testRowsWhoseAppIsGoneAreForgotten() {
        let usage = UsageStore()
        let stale = row("menu:Settings/Old app settings", .shell("open 'gone://settings'"))
        let kept = row("menu:Settings/Sight settings", .shell("open 'sight://settings'"))
        usage.record(stale, query: LaunchQuery(raw: "old"))
        usage.record(kept, query: LaunchQuery(raw: "sight"))
        usage.toggleFavourite(stale)
        let forgotten = usage.forgetRows { row in
            StaleTargets.targets(of: row).contains(.scheme("gone"))
        }
        XCTAssertEqual(forgotten, [stale.id])
        XCTAssertEqual(usage.recents().map(\.id), [kept.id])
        XCTAssertTrue(usage.favourites().isEmpty)
        XCTAssertTrue(usage.hasUnsavedChanges)
    }
}
