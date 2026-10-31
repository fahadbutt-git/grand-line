import AppKit
import BrowserKit
import LaunchKit

/// Starts the shared services and the menu bar, and takes the file viewer's
/// Apple events (R19): open folders ('odoc') and reveal items ('misc'/'mvis').
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let services = Services.shared
    private var launchedWithRequest = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let events = NSAppleEventManager.shared()
        for event in FileViewerRequest.handledEvents {
            events.setEventHandler(self, andSelector: #selector(handle(_:withReply:)), forEventClass: event.eventClass, andEventID: event.eventID)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(workspaces: self)
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        services.start()
        if !launchedWithRequest, WindowManager.shared.isEmpty {
            WindowManager.shared.newWindow(at: services.paths.home)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        services.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.newWindow(at: services.paths.home) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        route(.open(urls))
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
        let controller = WindowManager.shared.newWindow(at: services.paths.home)
        if command != .newWindow { controller.model.perform(command) }
    }

    /// With no browser window, only commands that make sense from nothing run,
    /// and never while a dialog's field is being typed in.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performBrowserCommand(_:)),
              let raw = menuItem.representedObject as? String, let command = BrowserCommand(rawValue: raw) else { return true }
        if let editing = TextFieldGuard.validate(menuItem, command, in: NSApp.keyWindow) { return editing }
        if NSApp.modalWindow != nil { return false }
        return CommandCatalog.spec(command).menu == .go || [.newWindow, .newTab, .find, .connectToServer].contains(command)
    }

    @objc func openSettings(_ sender: Any?) {
        let file = services.paths.settings
        if !FileManager.default.fileExists(atPath: file.path) {
            try? JSONFile<LogPoseSettings>(file).write(LogPoseSettings(places: nil, projectFolders: [], projects: []))
        }
        NSWorkspace.shared.open(file)
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
