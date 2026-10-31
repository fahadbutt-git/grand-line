import AppKit

/// The shared name index (Grand Line Index) as the launcher sees it: a file
/// made on disk is found within moments, and a launcher started again has
/// results at once because the index lives in the service, not in the app.
///
/// The service runs as its own launchd job for the journey, with the fixture
/// as its home and its own Mach service name, so the Mac's installed index of
/// the real home folder is never touched or asked.
enum IndexJourneys {
    static let label = "com.grandline.index.journey"

    static var all: [Journey] { [indexService] }

    static var indexService: Journey {
        Journey("launcher-index-service", role: LauncherJourneys.role,
                summary: "the shared index finds a new file within 2 s and answers a restarted launcher at once",
                waitsForWindow: false, window: { ctx in ctx.panel() }, rules: LauncherJourneys.rules,
                cleanup: { ctx in ctx.stopIndexService() }, steps: [
            step("start Grand Line Index with the fixture home", timeout: 60, layout: false) { ctx in
                try ctx.startIndexService()
                let snapshot = ctx.home.appendingPathComponent("Library/Application Support/Grand Line Index/names.index")
                let ms = try ctx.time("the service's first walk to be saved", timeout: 45, poll: 0.1) {
                    FileManager.default.fileExists(atPath: snapshot.path)
                }
                ctx.metric("service first walk", ms)
            },
            step("start the launcher again, now asking the service", layout: false) { ctx in
                ctx.quit()
                ctx.extraEnv[IndexJourneys.serviceKey] = IndexJourneys.label
                try ctx.launch(waitForWindow: false)
            },
            step("a new file is found within 2 s") { ctx in
                try ctx.showPanel(metric: "time to visible")
                let name = "conj probe 7Q.txt"
                let file = ctx.home.appendingPathComponent("Documents/Index Probe/" + name)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let made = Date()
                try Data("probe\n".utf8).write(to: file)
                // The launcher searches as it is typed to, so type again until it shows.
                var shown = false
                while !shown, Date().timeIntervalSince(made) < 2 {
                    try ctx.replaceQuery("probe 7q")
                    let until = Date().addingTimeInterval(0.3)
                    while !shown, Date() < until {
                        shown = ctx.panelTexts().contains { $0.hasPrefix("conj probe 7Q") }
                        if !shown { Input.pause(0.03) }
                    }
                }
                let ms = Date().timeIntervalSince(made) * 1000
                ctx.metric("new file to result", ms)
                try ctx.check(shown, "\(name) was not found within 2 s of being made; shown: \(ctx.panelTexts().prefix(15))")
                try ctx.key("escape"); try ctx.key("escape")
            },
            step("a file made while the launcher is closed is there the moment it opens") { ctx in
                ctx.quit()
                let name = "conj while closed.txt"
                let file = ctx.home.appendingPathComponent("Documents/Index Probe/" + name)
                try Data("probe\n".utf8).write(to: file)
                // Only the service saw this file: a copy read from the snapshot would not have it.
                Input.pause(1)
                // Two separate times, so a slow launch is not blamed on the
                // search: launch to a visible panel, and the typing to the result.
                let launched = Date()
                try ctx.launch(waitForWindow: false)
                ctx.metric("launch to app running", Date().timeIntervalSince(launched) * 1000)
                try ctx.showPanel(metric: "open to visible after restart")
                let ready = Date().timeIntervalSince(launched) * 1000
                ctx.metric("launch to visible panel", ready)
                try ctx.check(ready <= IndexJourneys.launchLimit,
                              "the panel took \(Int(ready)) ms from launch to visible (limit \(Int(IndexJourneys.launchLimit)) ms)")
                let found = { ctx.panelTexts().contains { $0.hasPrefix("conj while closed") } }
                let typingStarted = Date()
                Input.type("conj while cl")
                let typed = Date()
                ctx.metric("typing", typed.timeIntervalSince(typingStarted) * 1000)
                try ctx.wait("\(name) in the results", timeout: 5, poll: 0.01) { found() }
                let lastKey = Date().timeIntervalSince(typed) * 1000
                ctx.metric("first key to first result after restart", Date().timeIntervalSince(typingStarted) * 1000)
                ctx.metric("last key to first result after restart", lastKey)
                try ctx.check(lastKey <= IndexJourneys.resultLimit,
                              "the first result came \(Int(lastKey)) ms after the last key once the launcher started again (limit \(Int(IndexJourneys.resultLimit)) ms)")
                try ctx.key("escape"); try ctx.key("escape")
            },
        ])
    }

    static let serviceKey = "GRAND_LINE_INDEX_SERVICE"
    /// From starting the launcher to its panel on screen with the field ready (CI machines included).
    static let launchLimit: Double = 1500
    /// From the last key typed to the file in the results.
    static let resultLimit: Double = 500
}

extension Ctx {
    private var indexPlist: URL {
        dir.appendingPathComponent(IndexJourneys.label + ".plist")
    }

    private var launchDomain: String { "gui/\(getuid())" }

    /// Registers the journey's own index agent with launchd, from the built
    /// Grand Line Index.app next to the apps under test.
    func startIndexService() throws {
        guard let config = options.config, let folder = options.appsFolder,
              let entry = try AppEntry.load(config)["index"] else {
            throw StepFailure("apps.tsv names no app for the role index")
        }
        let program = folder.appendingPathComponent(entry.name + ".app/Contents/MacOS/" + entry.product)
        try check(FileManager.default.isExecutableFile(atPath: program.path), "no index agent at \(program.path)")
        stopIndexService()
        let job: [String: Any] = [
            "Label": IndexJourneys.label,
            "ProgramArguments": [program.path, "--serve"],
            "MachServices": [IndexJourneys.label: true],
            "EnvironmentVariables": [
                "HOME": home.path,
                "CFFIXED_USER_HOME": home.path,
                IndexJourneys.serviceKey: IndexJourneys.label,
                "GRAND_LINE_JOURNEY": "1",
            ],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "StandardErrorPath": dir.appendingPathComponent("index-service.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try data.write(to: indexPlist)
        let result = Shell.run("/bin/launchctl", ["bootstrap", launchDomain, indexPlist.path], timeout: 20)
        try check(result.status == 0, "launchctl bootstrap failed: \(result.output)")
        note("index service: launchd job \(IndexJourneys.label) with the fixture home")
    }

    /// Removes the journey's agent; nothing happens when it is not loaded.
    func stopIndexService() {
        _ = Shell.run("/bin/launchctl", ["bootout", launchDomain + "/" + IndexJourneys.label], timeout: 20)
    }
}
