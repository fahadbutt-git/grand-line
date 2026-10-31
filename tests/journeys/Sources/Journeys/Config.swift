import Foundation

/// One app from tests/journeys/apps.tsv, the only place app names live.
struct AppEntry {
    /// What the app is for: files, launcher, notch. Journeys refer to this.
    let role: String
    let folder: String
    let product: String
    let name: String
    let bundleID: String
    let urlScheme: String?
    let idPrefix: String

    static func load(_ url: URL) throws -> [String: AppEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var out: [String: AppEntry] = [:]
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7 else { throw StepFailure("apps.tsv: expected 7 tab-separated fields in \"\(line)\"") }
            out[f[0]] = AppEntry(role: f[0], folder: f[1], product: f[2], name: f[3], bundleID: f[4],
                                 urlScheme: f[5] == "-" ? nil : f[5], idPrefix: f[6])
        }
        return out
    }

    func id(_ suffix: String) -> String { idPrefix + "." + suffix }
}

struct Options {
    var appsFolder: URL?
    var fixtureScript: URL?
    var config: URL?
    var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("journey-results")
    var only: [String] = []
    var github = false
    var list = false
    var checkPermissions = false
    var prompt = false
    var quitRunning = false
    var stepTimeout: TimeInterval = 30
    var totalTimeout: TimeInterval = 1500
    /// Milliseconds a panel may take to appear before the step fails.
    var showLimit: Double = 3000

    static let usage = """
    journeys --apps DIR --fixture-script FILE [options]

      --apps DIR              folder with the built .app bundles
      --fixture-script FILE   tests/journeys/make-fixture.sh (run before each journey)
      --config FILE           apps.tsv (default: next to the fixture script)
      --out DIR               screenshots and results (default ./journey-results)
      --only A,B              roles (files, launcher, notch) or journey names or prefixes
      --list                  list the journeys and exit
      --github                print GitHub Actions annotations and a step summary
      --check-permissions     report Accessibility and Screen Recording, exit 0 if both granted
      --prompt                with --check-permissions: ask macOS for them
      --quit-running          quit a running copy of an app under test first
      --step-timeout SECONDS  default 30
      --total-timeout SECONDS default 1500
      --show-limit MS         slowest allowed time for the launcher to appear (default 3000)
    """

    static func parse(_ args: [String]) throws -> Options {
        var o = Options()
        var i = 0
        func value() throws -> String {
            i += 1
            guard i < args.count else { throw StepFailure("\(args[i - 1]) needs a value\n\n\(usage)") }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--apps": o.appsFolder = URL(fileURLWithPath: try value())
            case "--fixture-script": o.fixtureScript = URL(fileURLWithPath: try value())
            case "--config": o.config = URL(fileURLWithPath: try value())
            case "--out": o.output = URL(fileURLWithPath: try value())
            case "--only": o.only = try value().split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            case "--github": o.github = true
            case "--list": o.list = true
            case "--check-permissions": o.checkPermissions = true
            case "--prompt": o.prompt = true
            case "--quit-running": o.quitRunning = true
            case "--step-timeout": o.stepTimeout = TimeInterval(try value()) ?? o.stepTimeout
            case "--total-timeout": o.totalTimeout = TimeInterval(try value()) ?? o.totalTimeout
            case "--show-limit": o.showLimit = Double(try value()) ?? o.showLimit
            case "-h", "--help": print(usage); exit(0)
            default: throw StepFailure("unknown option \(args[i])\n\n\(usage)")
            }
            i += 1
        }
        if o.config == nil, let script = o.fixtureScript {
            o.config = script.deletingLastPathComponent().appendingPathComponent("apps.tsv")
        }
        return o
    }

    func selects(_ journey: Journey) -> Bool {
        only.isEmpty || only.contains { journey.role == $0 || journey.name == $0 || journey.name.hasPrefix($0) }
    }
}
