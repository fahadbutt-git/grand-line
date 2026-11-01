import AppKit
import ApplicationServices
import CoreServices
import LauncherKit

/// Definitions from the dictionaries macOS ships (Dictionary Services).
enum DictionaryLookup {
    static func define(_ word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range) else { return nil }
        return definition.takeRetainedValue() as String
    }
}

/// The running apps, for "quit".
enum RunningApps {
    static func list() -> [ProcessEntry] {
        let me = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != me, let name = app.localizedName else { return nil }
            return ProcessEntry(pid: app.processIdentifier, name: name, bundlePath: app.bundleURL?.path)
        }
    }
}

/// Keystrokes into the app that was in front (needs Accessibility).
enum Keystrokes {
    static func pasteCommand() {
        press(KeyShortcut("v"))
    }

    /// Posts the key combination at the HID level, where global shortcuts see it too.
    @discardableResult
    static func press(_ shortcut: KeyShortcut) -> Bool {
        guard let code = shortcut.virtualKey else { return false }
        var flags: CGEventFlags = []
        if shortcut.command { flags.insert(.maskCommand) }
        if shortcut.shift { flags.insert(.maskShift) }
        if shortcut.option { flags.insert(.maskAlternate) }
        if shortcut.control { flags.insert(.maskControl) }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Asks for Accessibility when it is missing. Returns whether it is granted.
    static func allowed() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for character in text {
            var units = Array(String(character).utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}

/// App icons, read once per path, off the main thread: asking Launch
/// Services for an icon and drawing it can take a moment each on a slow
/// disk, and a list of app rows asks for several at once. Until an icon is
/// read the row shows a plain symbol; the window redraws, once per turn of
/// the run loop, when icons arrive. At most `limit` are kept (apps and
/// running processes only, so it rarely fills); past it, it starts over.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]
    private static var loading: Set<String> = []
    private static var redrawPending = false
    static let limit = 400
    /// Redraws the window; set by the panel.
    static var onLoad: () -> Void = {}

    /// The icon when it has been read; otherwise nil, and it is read now in the background.
    static func cached(_ path: String) -> NSImage? {
        if let icon = icons[path] { return icon }
        load(path)
        return nil
    }

    private static func load(_ path: String) {
        guard loading.insert(path).inserted else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let drawn = LoadedIcon(image: IconCache.render(NSWorkspace.shared.icon(forFile: path)))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    IconCache.loading.remove(path)
                    if IconCache.icons.count >= IconCache.limit { IconCache.icons.removeAll(keepingCapacity: true) }
                    IconCache.icons[path] = drawn.image
                    IconCache.redrawSoon()
                }
            }
        }
    }

    /// Draws the icon at the size rows show it (20 points, 2x), so nothing is
    /// decoded later on the main thread.
    nonisolated private static func render(_ icon: NSImage) -> NSImage {
        var rect = NSRect(x: 0, y: 0, width: 40, height: 40)
        guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return icon }
        return NSImage(cgImage: cg, size: NSSize(width: 20, height: 20))
    }

    private static func redrawSoon() {
        guard !redrawPending else { return }
        redrawPending = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                IconCache.redrawPending = false
                IconCache.onLoad()
            }
        }
    }
}

/// An icon read in the background, handed to the main thread.
private struct LoadedIcon: @unchecked Sendable {
    let image: NSImage
}
