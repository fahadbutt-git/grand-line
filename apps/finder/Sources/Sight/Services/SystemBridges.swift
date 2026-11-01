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

/// App icons, read once per path. At most `limit` are kept (apps and
/// running processes only, so it rarely fills); past it, it starts over.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]
    static let limit = 400

    static func icon(_ path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        if icons.count >= limit { icons.removeAll(keepingCapacity: true) }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
