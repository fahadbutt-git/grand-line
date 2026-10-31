import AppKit
import ApplicationServices

// journeys: drives the built apps through every use case. See Options.usage.

setvbuf(stdout, nil, _IOLBF, 0)

/// Journeys that change the Mac's own settings (dark mode, Dock, sound), run
/// only when asked for: CI asks; on your own Mac name them with --only.
let changesTheMac: Set<String> = ["launcher-settings"]

let allJourneys: [Journey] = FilesJourneys.all + LauncherJourneys.all + NotchJourneys.all

func fatal(_ message: String) -> Never {
    FileHandle.standardError.write(("journeys: " + message + "\n").data(using: .utf8)!)
    exit(2)
}

let options: Options
do {
    options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fatal("\(error)")
}

if options.list {
    for journey in allJourneys {
        let optIn = changesTheMac.contains(journey.name) ? "  (changes system settings; run with --only \(journey.name))" : ""
        print("\(journey.name)\t\(journey.role)\t\(journey.steps.count) steps\t\(journey.summary)\(optIn)")
    }
    exit(0)
}

if options.checkPermissions {
    let trusted = options.prompt
        ? AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        : AXIsProcessTrusted()
    var screen = CGPreflightScreenCaptureAccess()
    if !screen, options.prompt { screen = CGRequestScreenCaptureAccess() }
    print("Accessibility: \(trusted ? "granted" : "NOT granted")")
    print("Screen Recording: \(screen ? "granted" : "NOT granted")")
    exit(trusted && screen ? 0 : 1)
}

guard let appsFolder = options.appsFolder else { fatal("--apps is required\n\n\(Options.usage)") }
guard let script = options.fixtureScript, FileManager.default.fileExists(atPath: script.path) else {
    fatal("--fixture-script is required and must exist\n\n\(Options.usage)")
}
guard let configURL = options.config else { fatal("no apps.tsv") }
let apps: [String: AppEntry]
do { apps = try AppEntry.load(configURL) } catch { fatal("\(error)") }
_ = appsFolder

guard AXIsProcessTrusted() else {
    if options.github {
        print("::error title=journeys::Accessibility is not granted to the journey driver (or the process that started it), so no app could be driven. See the grant step's output.")
    }
    fatal("Accessibility is not granted. Allow the app you run this from (Terminal, or the CI agent) in System Settings > Privacy & Security > Accessibility.")
}
if !CGPreflightScreenCaptureAccess() {
    print("Screen Recording is not granted: screenshots will show only the desktop, and colour checks are skipped.")
    if options.github { print("::warning title=journeys::Screen Recording is not granted, so screenshots are empty and colour checks are skipped") }
}

AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 3)

let selected = allJourneys.filter { journey in
    guard options.selects(journey) else { return false }
    // Opt-in journeys run only when named, or in CI.
    if changesTheMac.contains(journey.name) {
        return options.only.contains(journey.name) || ProcessInfo.processInfo.environment["CI"] != nil
    }
    return true
}
if selected.isEmpty { fatal("no journeys match --only \(options.only.joined(separator: ","))") }

let runner = Runner(options: options, apps: apps)
runner.run(selected)
exit(runner.results.allSatisfy(\.passed) ? 0 : 1)
