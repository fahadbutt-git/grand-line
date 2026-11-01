import AppKit
import AppRuntime
import BrowserKit
import LaunchKit

/// Starts the shared services and the menu bar, and takes the file viewer's
/// Apple events (R19): open folders ('odoc') and reveal items ('misc'/'mvis').
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let services = Services.shared
    private var launchedWithRequest = false
    /// ~/Library/Logs/grand-line/nexus-runtime.log: stalls and crashes.
    private let runtimeLog = AppLog(name: "nexus-runtime")
    private lazy var watchdog = HangWatchdog(log: runtimeLog)
    private lazy var crashRecord = CrashGuard(name: "nexus", log: runtimeLog)
    private var activeObservers: [NSObjectProtocol] = []
    private var termination: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let events = NSAppleEventManager.shared()
        for event in FileViewerRequest.handledEvents {
            events.setEventHandler(self, andSelector: #selector(handle(_:withReply:)), forEventClass: event.eventClass, andEventID: event.eventID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nexus is opened by hand, so it always runs; the record only tells
        // the log about a crash.
        crashRecord.launch(displayName: "Nexus", staysDownAfterLoop: false)
        termination = TerminationSignal.handle { DispatchQueue.main.async { MainActor.assumeIsolated { NSApp.terminate(nil) } } }
        watchMainThread()
        NSApp.mainMenu = MainMenu.build(workspaces: self)
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        services.start()
        if !launchedWithRequest, WindowManager.shared.isEmpty {
            WindowManager.shared.newWindow(from: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
        crashRecord.quitCleanly()
    }

    /// The hang watchdog, while Nexus is the app in front.
    private func watchMainThread() {
        let center = NotificationCenter.default
        let dog = watchdog
        activeObservers = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in dog.setActive(true) },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in dog.setActive(false) },
        ]
        dog.setActive(NSApp.isActive)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.newWindow(from: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Folders to show, and `nexus://settings[/pane]`, which opens Settings
    /// (the launcher's "nexus settings" and the main menu use it).
    func application(_ application: NSApplication, open urls: [URL]) {
        let settings = urls.filter { $0.scheme?.lowercased() == "nexus" }
        for url in settings where (url.host ?? "") == "settings" {
            let pane = url.pathComponents.dropFirst().first
            launchedWithRequest = launchedWithRequest || WindowManager.shared.isEmpty
            NexusSettingsWindow.shared.show(pane: pane)
        }
        let files = urls.filter { $0.isFileURL }
        if !files.isEmpty { route(.open(files)) }
    }

    @objc func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let request = FileViewerRequest.parse(event) else { return }
        route(request)
    }

    private func route(_ request: FileViewerRequest) {
        launchedWithRequest = true
        let windows = ViewerRouting.windows(for: request) { url in
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            return exists && isFolder.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path)
        }
        for window in windows { WindowManager.shared.show(window) }
    }

    // MARK: Menu actions with no window

    /// Reached when no browser window is key: text commands go to a field in a
    /// dialog; anything else opens a window first.
    @objc func performBrowserCommand(_ sender: Any?) {
        guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
              let command = BrowserCommand(rawValue: raw) else { return }
        if TextFieldGuard.forward(command, in: NSApp.keyWindow) { return }
        // Another window is in front (Settings, a panel): Close Window closes
        // it, as Cmd+W does for every window on a Mac.
        if command == .closeWindow || command == .closeAllWindows, let window = NSApp.keyWindow {
            window.performClose(nil)
            return
        }
        let controller = WindowManager.shared.newWindow(from: nil)
        if command != .newWindow { controller.model.perform(command) }
    }

    /// With no browser window, only commands that make sense from nothing run,
    /// and never while a dialog's field is being typed in.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performBrowserCommand(_:)),
              let raw = menuItem.representedObject as? String, let command = BrowserCommand(rawValue: raw) else { return true }
        if let editing = TextFieldGuard.validate(menuItem, command, in: NSApp.keyWindow) { return editing }
        if NSApp.modalWindow != nil { return false }
        if command == .closeWindow || command == .closeAllWindows {
            return NSApp.keyWindow?.styleMask.contains(.closable) == true
        }
        return CommandCatalog.spec(command).menu == .go || [.newWindow, .newTab, .find, .connectToServer].contains(command)
    }

    /// Nexus › Settings… (Cmd+,): the Settings window.
    @objc func openSettings(_ sender: Any?) {
        NexusSettingsWindow.shared.show()
    }

    /// Nexus › Open Configuration Folder: ~/.config/grand-line/nexus.
    @objc func openConfigurationFolder(_ sender: Any?) {
        let folder = services.paths.settingsFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc func reloadSettings(_ sender: Any?) {
        services.reloadConfig()
    }

    // MARK: Workspaces menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let names = services.workspaces.names()
        if names.isEmpty {
            menu.addItem(NSMenuItem(title: "No Saved Workspaces", action: nil, keyEquivalent: ""))
        }
        for name in names {
            let item = NSMenuItem(title: name, action: #selector(openWorkspace(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MainMenu.item(CommandCatalog.spec(.saveWorkspace)))
    }

    @objc func openWorkspace(_ sender: Any?) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String,
              let workspace = services.workspaces.load(name) else { return }
        WindowManager.shared.open(workspace)
    }
}
