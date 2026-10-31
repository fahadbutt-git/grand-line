import AppKit

/// Small modal questions: a name, an address, a yes or no.
@MainActor
enum Prompt {
    static func text(_ title: String, message: String = "", value: String = "", action: String = "OK") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = value
        field.lineBreakMode = .byTruncatingMiddle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func confirm(_ title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func problem(_ title: String, _ error: Error? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error?.localizedDescription ?? ""
        alert.runModal()
    }

    /// A folder chooser for Extract To and Move To.
    static func folder(_ title: String, start: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        return panel.runModal() == .OK ? panel.url : nil
    }
}
