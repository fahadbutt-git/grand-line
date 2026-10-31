import AppKit
import LauncherKit

/// Carries out the commands rows describe. The window is already hidden for
/// actions that close it, so pastes and menu clicks land in the app that was in front.
@MainActor
final class ActionPerformer {
    static let logPose = "com.grandline.logpose"
    let paths: GrandLinePaths
    var previousApp: NSRunningApplication?

    init(paths: GrandLinePaths) {
        self.paths = paths
    }

    func perform(_ command: ActionCommand) {
        switch command {
        case .open(let target):
            open(paths.expand(target))
        case .openURL(let text, let bundleID):
            openURL(text, bundleID: bundleID)
        case .reveal(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: paths.expand(path))])
        case .copyText(let text):
            copy(text)
        case .copyFile(let path):
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([URL(fileURLWithPath: paths.expand(path)) as NSURL])
        case .paste(let text):
            copy(text)
            inFrontApp { Keystrokes.pasteCommand() }
        case .typeText(let text):
            inFrontApp { Keystrokes.type(text) }
        case .pressKeys(let shortcut):
            guard Keystrokes.allowed() else { return }
            inFrontApp { if !Keystrokes.press(shortcut) { NSSound.beep() } }
        case .moveTo(let path):
            moveAsking(paths.expand(path))
        case .airDrop(let path):
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [URL(fileURLWithPath: paths.expand(path))])
        case .run(let executable, let arguments):
            launch(executable, arguments)
        case .shell(let line):
            launch("/bin/bash", ShellRunner.bashArguments(for: line, paths: paths))
        case .pressMenuItem(let pid, let path):
            inFrontApp { _ = MenuBarReader.press(pid: pid, path: path) }
        case .quit(let pid, let force):
            quit(pid, force: force)
        case .lookUp(let word):
            let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
            if let url = URL(string: "dict://" + encoded) { NSWorkspace.shared.open(url) }
        case .openWith, .quickLook, .setQuery, .toggleFavourite:
            break // handled by the window
        }
    }

    /// Folders open in Log Pose when it is installed; everything else in its default app.
    func open(_ target: String) {
        if target.contains("://") { return openURL(target, bundleID: nil) }
        let url = URL(fileURLWithPath: target)
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target, isDirectory: &isFolder)
        guard exists else { return NSSound.beep() }
        let isPackage = NSWorkspace.shared.isFilePackage(atPath: target)
        if isFolder.boolValue, !isPackage, let logPose = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.logPose) {
            NSWorkspace.shared.open([url], withApplicationAt: logPose, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openURL(_ text: String, bundleID: String?) {
        guard let url = URL(string: text) else { return NSSound.beep() }
        if let bundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Starts a program with the Grand Line PATH and does not wait for it.
    func launch(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: paths.expand(executable))
        process.arguments = arguments
        process.environment = ShellRunner.environment(paths: paths)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = URL(fileURLWithPath: paths.home)
        do { try process.run() } catch { NSSound.beep() }
    }

    func quit(_ pid: Int32, force: Bool) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = force ? app.forceTerminate() : app.terminate()
        } else {
            kill(pid, force ? SIGKILL : SIGTERM)
        }
    }

    /// Brings back the app that was in front, then acts in it once it is active.
    func inFrontApp(_ work: @escaping () -> Void) {
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Asks for a folder and moves the item there; an item of the same name is never replaced.
    func moveAsking(_ path: String) {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Move here"
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).deletingLastPathComponent)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let destination = folder.appendingPathComponent((path as NSString).lastPathComponent)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return NSSound.beep() }
        do { try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: destination) } catch { NSSound.beep() }
    }

    /// The apps that can open a file, for Open With.
    func openWithActions(_ path: String) -> [LaunchAction] {
        let url = URL(fileURLWithPath: paths.expand(path))
        return NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(20).map { app in
            let name = FileManager.default.displayName(atPath: app.path)
            return LaunchAction(name, symbol: "app", .run("/usr/bin/open", arguments: ["-a", app.path, url.path]))
        }
    }
}
