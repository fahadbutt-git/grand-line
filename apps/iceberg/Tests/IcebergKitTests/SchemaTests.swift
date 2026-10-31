import XCTest
@testable import IcebergKit

/// Config validation: types, allowed keys and ranges for iceberg.toml and
/// widget files, each problem with its file, line and a plain fix, and the
/// published iceberg.schema.json kept the same as the checks.
final class SchemaTests: XCTestCase {
    // MARK: Messages

    func testWidgetProblemsNameTheLineAndAFix() {
        let (w, issues) = WidgetConfig.parse(Data("""
        title = "Disk"
        command = "df -h"
        refesh = 60
        timeout = true
        icon = 5
        """.utf8), fileName: "disk.toml")
        XCTAssertNotNil(w, "warnings only, so the widget still loads")
        let byLine = Dictionary(grouping: issues, by: { $0.line ?? 0 })
        XCTAssertEqual(byLine[3]?.first?.message, "unknown key \"refesh\" (did you mean \"refresh\"?)")
        XCTAssertEqual(byLine[3]?.first?.fix, "Rename it to refresh.")
        XCTAssertTrue(byLine[4]?.first?.message.contains("\"timeout\" must be a number of seconds") ?? false)
        XCTAssertTrue(byLine[5]?.first?.message.contains("\"icon\" must be text in quotes, not a number") ?? false)
        XCTAssertEqual(byLine[5]?.first?.location, "disk.toml:5")
        XCTAssertTrue(issues.allSatisfy { $0.fix != nil }, "every problem says how to fix it: \(issues)")
    }

    func testMissingCommandIsAnErrorWithAFix() {
        let (w, issues) = WidgetConfig.parse(Data("title = \"Nothing\"".utf8), fileName: "n.toml")
        XCTAssertNil(w)
        let issue = issues.first { $0.severity == .error }
        XCTAssertEqual(issue?.fix, "Add a line like: command = \"date +%H:%M\"")
        XCTAssertNil(issue?.line)
    }

    func testSyntaxErrorsGetAFix() {
        let (_, issues) = WidgetConfig.parse(Data("title = Disk\ncommand = \"df\"".utf8), fileName: "d.toml")
        XCTAssertEqual(issues.first?.line, 1)
        XCTAssertEqual(issues.first?.location, "d.toml:1")
        XCTAssertTrue(issues.first?.fix?.contains("double quotes") ?? false)
    }

    func testJSONWidgetProblemsNameTheLine() {
        let json = """
        {
          "title": "J",
          "command": "date",
          "colour": "red"
        }
        """
        let (w, issues) = WidgetConfig.parse(Data(json.utf8), fileName: "j.json")
        XCTAssertNotNil(w)
        XCTAssertEqual(issues.first?.line, 4)
        XCTAssertEqual(JSONKeyLines.lines(in: json), ["title": 2, "command": 3, "colour": 4])
    }

    func testRepeatedAliasKeepsTheFirstLine() {
        let (w, issues) = WidgetConfig.parse(Data("title = \"T\"\ncommand = \"first\"\nscript = \"second\"".utf8), fileName: "r.toml")
        XCTAssertEqual(w?.command, "first")
        XCTAssertEqual(issues.first?.line, 3)
        XCTAssertTrue(issues.first?.message.contains("repeats") ?? false)
    }

    func testSettingsProblems() {
        let (s, issues) = IcebergSettings.parse("""
        open_on = "hover"
        hover_delay = 9
        open_on_click = true
        toggle_shortcut = "hyper+n"
        """)
        XCTAssertEqual(s.hoverDelay, IcebergSettings().hoverDelay)
        XCTAssertEqual(s.toggleShortcut, KeyShortcut.defaultToggle)
        XCTAssertEqual(issues.map(\.line), [2, 3, 4])
        XCTAssertEqual(issues[0].message, "\"hover_delay\" must be between 0 and 3; using 0.12")
        XCTAssertEqual(issues[0].fix, "Use a value from 0 to 3.")
        XCTAssertTrue(issues.allSatisfy { $0.severity == .warning && $0.fix != nil })
    }

    func testShortcutSetting() {
        XCTAssertEqual(IcebergSettings().toggleShortcut?.text, "ctrl+option+cmd+n")
        XCTAssertEqual(IcebergSettings.parse("toggle_shortcut = \"cmd+shift+space\"").0.toggleShortcut?.text, "shift+cmd+space")
        XCTAssertNil(IcebergSettings.parse("toggle_shortcut = \"\"").0.toggleShortcut)
        XCTAssertNil(IcebergSettings.parse("toggle_shortcut = \"none\"").0.toggleShortcut)
        XCTAssertEqual(IcebergSettings.parse("toggle_shortcut = \"⌃⌥⌘N\"").0.toggleShortcut, KeyShortcut.defaultToggle)
        let (s, issues) = IcebergSettings.parse("toggle_shortcut = \"n\"")
        XCTAssertEqual(s.toggleShortcut, KeyShortcut.defaultToggle, "a bad value keeps the default")
        XCTAssertEqual(issues.count, 1)
    }

    func testEveryKeyHasASummaryAndExample() {
        for schema in [ConfigSchema.settings, ConfigSchema.widget] {
            for key in schema.keys {
                XCTAssertFalse(key.summary.isEmpty, key.name)
                // The example must itself pass the check.
                let checked = schema.check([key.name: try! XCTUnwrap(Self.toml(key.example))], fileName: "x")
                XCTAssertNotNil(checked.values[key.name], "\(key.name) = \(key.example) is refused: \(checked.issues)")
                XCTAssertTrue(checked.issues.filter { $0.message.contains(key.name) && !$0.message.contains("missing") }.isEmpty,
                              "\(key.name) = \(key.example): \(checked.issues)")
            }
        }
    }

    static func toml(_ literal: String) -> TOMLValue? {
        (try? TOML.parse("v = " + literal))?["v"]
    }

    // MARK: The published schema

    private func publishedSchema() throws -> [String: JSONValue] {
        let url = appFolder.appendingPathComponent("Resources/Iceberg/iceberg.schema.json")
        return try XCTUnwrap(JSONValue.parse(Data(contentsOf: url)).objectValue)
    }

    func testPublishedSchemaMatchesTheChecks() throws {
        let root = try publishedSchema()
        let settings = try XCTUnwrap(root["properties"]?.objectValue)
        let widget = try XCTUnwrap(root["$defs"]?.objectValue?["widget"]?.objectValue)
        let widgetProperties = try XCTUnwrap(widget["properties"]?.objectValue)

        XCTAssertEqual(Set(settings.keys), Set(ConfigSchema.settings.names))
        let widgetNames = ConfigSchema.widget.keys.flatMap { [$0.name] + $0.aliases }
        XCTAssertEqual(Set(widgetProperties.keys), Set(widgetNames))
        XCTAssertEqual(widget["required"], .array(ConfigSchema.widget.keys.filter(\.required).map { .string($0.name) }))
        XCTAssertEqual(root["additionalProperties"], .bool(false))
        XCTAssertEqual(widget["additionalProperties"], .bool(false))

        for (schema, properties) in [(ConfigSchema.settings, settings), (ConfigSchema.widget, widgetProperties)] {
            for key in schema.keys {
                let property = try XCTUnwrap(properties[key.name]?.objectValue, key.name)
                XCTAssertEqual(property["description"]?.stringValue?.isEmpty, false, key.name)
                if case .choice(let words) = key.type {
                    XCTAssertEqual(property["enum"], .array(words.map { .string($0) }), key.name)
                }
                if let range = key.range {
                    let bounds = Self.bounds(property)
                    XCTAssertEqual(bounds.min, range.lowerBound, key.name)
                    XCTAssertEqual(bounds.max, range.upperBound, key.name)
                }
                let published = property["default"]?.tomlValue
                let declared = key.defaultValue.flatMap(Self.toml)
                XCTAssertEqual(published, declared, "default of \(key.name)")
            }
        }
    }

    /// minimum and maximum, directly or in an anyOf branch.
    static func bounds(_ property: [String: JSONValue]) -> (min: Double?, max: Double?) {
        if let lo = property["minimum"]?.doubleValue { return (lo, property["maximum"]?.doubleValue) }
        if case .array(let branches)? = property["anyOf"] {
            for b in branches {
                if let o = b.objectValue, let lo = o["minimum"]?.doubleValue { return (lo, o["maximum"]?.doubleValue) }
            }
        }
        return (nil, nil)
    }

    func testReadmeDocumentsEveryKey() throws {
        let readme = try String(contentsOf: appFolder.appendingPathComponent("README.md"), encoding: .utf8)
        for key in ConfigSchema.settings.keys + ConfigSchema.widget.keys {
            XCTAssertTrue(readme.contains("`\(key.name)`") || readme.contains("\(key.name) ="), "README.md does not mention \(key.name)")
        }
        XCTAssertTrue(readme.contains("iceberg.schema.json"))
    }

    func testTOMLDocumentLines() throws {
        let doc = try TOML.parseDocument("# c\na = 1\n\n[t]\nb = [\n 1,\n 2]\nc = \"x\"\n")
        XCTAssertEqual(doc.lines, ["a": 2, "t.b": 5, "t.c": 8])
        XCTAssertEqual(doc.values["t.c"], .string("x"))
    }
}
