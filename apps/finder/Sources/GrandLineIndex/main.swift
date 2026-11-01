import AppRuntime
import Foundation
import IndexKit
import IndexService
import ServiceManagement

// Grand Line Index: the background agent that keeps one name index of the home
// folder for Nexus and Sight. It has no window and no menu bar item. launchd
// runs it from Contents/Library/LaunchAgents/com.grandline.index.plist
// (registered with SMAppService), keeps it alive and starts it when an app
// connects to the com.grandline.index Mach service. Because it is its own app,
// it is the one that holds Full Disk Access.
//
//   GrandLineIndex --register     register the agent with launchd (setup runs this)
//   GrandLineIndex --unregister
//   GrandLineIndex --status       prints enabled, requires approval, not registered or not found
//   GrandLineIndex --serve        run the service (launchd does this)
//
// Opened with no arguments (by `open -b com.grandline.index`, which an app
// does when it cannot reach the service), it registers the agent if needed
// and exits; launchd then starts the service.

setvbuf(stdout, nil, _IOLBF, 0)

let plistName = "com.grandline.index.plist"
let environment = ProcessInfo.processInfo.environment
let serviceName = IndexServiceName.forService(environment)
let agent = SMAppService.agent(plistName: plistName)

func describe(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requires approval in System Settings > General > Login Items"
    case .notRegistered: return "not registered"
    case .notFound: return "not found (the app bundle has no \(plistName))"
    @unknown default: return "unknown (\(status.rawValue))"
    }
}

func register(quietly: Bool) -> Int32 {
    if agent.status == .enabled {
        if !quietly { print("Grand Line Index: \(describe(agent.status))") }
        return 0
    }
    do {
        try agent.register()
    } catch {
        if !quietly { print("Grand Line Index: could not register: \(error.localizedDescription)") }
    }
    let status = agent.status
    if !quietly { print("Grand Line Index: \(describe(status))") }
    if status == .requiresApproval, !quietly { SMAppService.openSystemSettingsLoginItems() }
    return status == .enabled ? 0 : 1
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
    exit(register(quietly: false))
case "--unregister":
    do {
        try agent.unregister()
        print("Grand Line Index: unregistered")
        exit(0)
    } catch {
        print("Grand Line Index: could not unregister: \(error.localizedDescription)")
        exit(1)
    }
case "--status":
    print(describe(agent.status))
    exit(agent.status == .enabled ? 0 : 1)
case "--serve":
    serve()
case "-h", "--help":
    print("usage: GrandLineIndex [--register | --unregister | --status | --serve]")
    exit(0)
default:
    // launchd names the job it started in XPC_SERVICE_NAME.
    if environment["XPC_SERVICE_NAME"] == serviceName { serve() }
    exit(register(quietly: true))
}
