import XCTest
@testable import DenDenKit

/// The widgets shipped in examples/ must load without a single warning,
/// and their scripts must print what Den Den expects.
final class ExampleWidgetTests: XCTestCase {
    let examples = appFolder.appendingPathComponent("Resources/DenDen/examples/widgets")

    func testBundledLicenceMatches() throws {
        let a = try Data(contentsOf: appFolder.appendingPathComponent("LICENSE"))
        let b = try Data(contentsOf: appFolder.appendingPathComponent("Resources/DenDen/LICENSE.txt"))
        XCTAssertEqual(a, b, "copy LICENSE to Resources/DenDen/LICENSE.txt")
    }

    func testExamplesLoadCleanly() {
        let r = WidgetLoader.load(from: examples)
        XCTAssertEqual(r.issues, [])
        XCTAssertEqual(r.widgets.map(\.id), ["weather", "services"])
        XCTAssertEqual(r.widgets.first?.refresh, .interval(1800))
        XCTAssertEqual(r.widgets.last?.refresh, .onOpen)
    }

    func testServicesScriptPrintsJSON() {
        let home = TempFolder()
        home.write(".local/state/grand-line/toggles/docker", "")
        let r = CommandRunner(environment: CommandRunner.defaultEnvironment(home: home.url.path, base: ["PATH": "/usr/bin:/bin", "HOME": home.url.path]))
            .run("/bin/sh ./services.sh", timeout: 10, workingDirectory: examples)
        let shown = CommandOutputParser.display(for: r)
        XCTAssertFalse(shown.failed, r.stderr)
        XCTAssertTrue(shown.text.hasPrefix("Docker on"), shown.text)
        XCTAssertEqual(shown.color, .theme(.highlight))
    }

    func testWeatherScriptWithoutLocationAsksForIt() {
        let home = TempFolder()
        let r = CommandRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": home.url.path])
            .run("/bin/sh ./weather.sh", timeout: 10, workingDirectory: examples)
        XCTAssertEqual(CommandOutputParser.display(for: r).text, "Set LOCATION")
    }

    func testWeatherScriptReadsPersonalEnv() {
        let home = TempFolder()
        home.write(".config/grand-line/personal.env", "NAME=\"Jane Smith\"\nLOCATION=\"not numbers\"\n")
        let r = CommandRunner(environment: ["PATH": "/usr/bin:/bin", "HOME": home.url.path])
            .run("/bin/sh ./weather.sh", timeout: 10, workingDirectory: examples)
        XCTAssertEqual(CommandOutputParser.display(for: r).text, "Bad LOCATION")
    }
}
