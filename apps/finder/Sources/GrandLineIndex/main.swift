import AppRuntime
import Foundation
import IndexKit
import IndexService
import ServiceManagement

// Grand Line Index: the background agent that keeps one name index of the home
// folder for Sight. It has no window and no menu bar item. launchd
// runs it from ~/Library/LaunchAgents/com.grandline.index.plist, which setup
// writes and loads (lib/service-agents.sh), keeps it alive and starts it when
// an app connects to the com.grandline.index Mach service. Because it is its
// own app, it is the one that holds Full Disk Access.
//
//   GrandLineIndex --register     start the agent: kickstart it when launchd has
//                                 it, load its plist when not (written first
//                                 when missing)
//   GrandLineIndex --unregister   remove the Login Items registration
//                                 (SMAppService) of a copy from before the
//                                 agent moved to ~/Library/LaunchAgents
//   GrandLineIndex --status       prints enabled, not loaded or not installed
//   GrandLineIndex --serve        run the service (launchd does this)
//
// Opened with no arguments (by `open -b com.grandline.index`, which an app
// does when it cannot reach the service), it starts the agent the same way
// as --register and exits.

setvbuf(stdout, nil, _IOLBF, 0)

let environment = ProcessInfo.processInfo.environment
let serviceName = IndexServiceName.forService(environment)
let domain = "gui/\(getuid())"
let agentPlist = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/LaunchAgents/\(serviceName).plist")
/// The registration of copies built before the agent left the app bundle.
let legacyAgent = SMAppService.agent(plistName: "\(IndexServiceName.standard).plist")

@discardableResult
func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return (process.terminationStatus, output)
}

func loaded() -> Bool {
    launchctl(["print", "\(domain)/\(serviceName)"]).status == 0
}

/// The plist setup writes (apps/finder/LaunchAgents/GrandLineIndex.plist),
/// for a copy installed without setup. Setup puts its own text in place when
/// it next runs.
func writeAgentPlist() throws {
    let program = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    let job: [String: Any] = [
        "Label": serviceName,
        "Program": program,
        "ProgramArguments": [program, "--serve"],
        "MachServices": [serviceName: true],
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],
        "ThrottleInterval": 30,
        "ProcessType": "Adaptive",
        "ExitTimeOut": 30,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    try FileManager.default.createDirectory(at: agentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: agentPlist, options: .atomic)
}

func describeStatus() -> String {
    if loaded() { return "enabled (launchd job \(domain)/\(serviceName))" }
    if FileManager.default.fileExists(atPath: agentPlist.path) {
        return "not loaded (\(agentPlist.path) is there; GrandLineIndex --register loads it)"
    }
    return "not installed (no \(agentPlist.path); setup writes it)"
}

/// Starts the agent: kickstart when launchd has it (nothing happens when it
/// runs already), otherwise loads the plist. Never registers anything with
/// Login Items, so macOS has nothing new to announce.
func start(quietly: Bool) -> Int32 {
    func say(_ text: String) { if !quietly { print("Grand Line Index: \(text)") } }
    if loaded() {
        launchctl(["kickstart", "\(domain)/\(serviceName)"])
        say(describeStatus())
        return 0
    }
    if !FileManager.default.fileExists(atPath: agentPlist.path) {
        // Only the Mac's own agent; a journey's job is written by the journey.
        guard serviceName == IndexServiceName.standard else {
            say(describeStatus())
            return 1
        }
        do { try writeAgentPlist() } catch {
            say("could not write \(agentPlist.path): \(error.localizedDescription)")
            return 1
        }
    }
    let result = launchctl(["bootstrap", domain, agentPlist.path])
    if loaded() {
        say(describeStatus())
        return 0
    }
    say("could not load \(agentPlist.path): \(result.output.isEmpty ? "launchctl said nothing" : result.output)")
    return 1
}

func unregisterLegacy() -> Int32 {
    let before = legacyAgent.status
    do {
        try legacyAgent.unregister()
        print("Grand Line Index: the old Login Items registration is removed")
        return 0
    } catch {
        if before != .enabled && before != .requiresApproval {
            print("Grand Line Index: no old Login Items registration")
            return 0
        }
        print("Grand Line Index: could not remove the old Login Items registration: \(error.localizedDescription)")
        return 1
    }
}

func serve() -> Never {
    // launchd starts the agent again after a crash (KeepAlive, SuccessfulExit
    // false); after three crashes in ten minutes it stays down, cleanly, and
    // says so once. The next app that connects starts it again.
    let log = AppLog(name: "index")
    let record = CrashGuard(name: "index", log: log)
    guard record.launch(displayName: "Grand Line Index") else { exit(0) }
    let core = IndexServiceCore(locations: IndexLocations())
    core.start()
    // Sight and Iceberg live in the menu bar with no Dock icon to reopen
    // them from: one that crashed is started again in the background, at
    // most once a minute (not during the journeys, which quit them on purpose).
    let watcher = CrashWatcher(apps: [.init(name: "sight", bundleID: "com.grandline.sight"),
                                      .init(name: "iceberg", bundleID: "com.grandline.iceberg")], log: log)
    if environment["GRAND_LINE_JOURNEY"] != "1" { watcher.start() }
    // Ad hoc or unsigned: said once per start, in the log, so it is not taken
    // for the certificate check (see CodeSigning.Trust).
    if let warning = CodeSigning.trustWarning(CodeSigning.own) { log.write(warning) }
    let delegate = IndexListenerDelegate(core: core, clientRequirement: IndexListenerDelegate.standardRequirement())
    let listener = NSXPCListener(machServiceName: serviceName)
    listener.delegate = delegate
    listener.resume()
    // launchd sends SIGTERM at logout and on bootout: save first.
    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            record.quitCleanly()
            core.saveAndExit()
        }
        source.resume()
        return source
    }
    withExtendedLifetime((listener, delegate, signals, watcher)) {
        dispatchMain()
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--register":
    exit(start(quietly: false))
case "--unregister":
    exit(unregisterLegacy())
case "--status":
    print(describeStatus())
    exit(loaded() ? 0 : 1)
case "--serve":
    serve()
case "-h", "--help":
    print("usage: GrandLineIndex [--register | --unregister | --status | --serve]")
    exit(0)
default:
    // launchd names the job it started in XPC_SERVICE_NAME.
    if environment["XPC_SERVICE_NAME"] == serviceName { serve() }
    exit(start(quietly: true))
}
