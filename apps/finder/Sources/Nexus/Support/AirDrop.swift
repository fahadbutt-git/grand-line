import AppKit

/// AirDrop as Finder has it: a sidebar item and Go > AirDrop (Cmd+Shift+R)
/// open the AirDrop window, and files dropped on the item or sent from the
/// selection go out through the system AirDrop service.
@MainActor
enum AirDrop {
    static let bundleID = "com.apple.finder.Open-AirDrop"
    static let appPath = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"

    /// The AirDrop window, by bundle id or, failing that, by its path inside Finder.
    static func openWindow() {
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? (FileManager.default.fileExists(atPath: appPath) ? URL(fileURLWithPath: appPath) : nil)
        guard let app else {
            Prompt.problem("AirDrop is not available on this Mac.")
            return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async { Prompt.problem("AirDrop could not be opened.", error) }
        }
    }

    static func send(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            Prompt.problem("AirDrop is not available for these items.")
            return
        }
        service.perform(withItems: urls)
    }
}
