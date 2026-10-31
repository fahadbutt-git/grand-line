import AppKit
import CoreGraphics

/// Keystrokes and clicks, posted as hardware events so they go through the
/// same path as a person's: the window server, the menu bar's key equivalents,
/// the focused view.
enum Input {
    static let source = CGEventSource(stateID: .hidSystemState)

    /// US layout key codes.
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "left": 123, "right": 124, "down": 125, "up": 126, "forwarddelete": 117,
    ]

    /// Characters typed with Shift on a US keyboard, and the key under them.
    static let shifted: [Character: String] = [
        "+": "=", "_": "-", "?": "/", "*": "8", "(": "9", ")": "0", ":": ";", "\"": "'", "<": ",",
        ">": ".", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "~": "`",
        "{": "[", "}": "]", "|": "\\",
    ]

    static let functionKeys: Set<String> = ["f1", "f2", "f3", "f4", "f5", "f6", "left", "right", "down", "up", "forwarddelete"]

    /// "cmd+shift+n", "f2", "return", "ctrl+opt+cmd+5".
    static func press(_ combo: String) throws {
        var flags: CGEventFlags = []
        var keyName = ""
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: keyName = part
            }
        }
        guard let code = codes[keyName] else { throw StepFailure("no key code for \"\(combo)\"") }
        if functionKeys.contains(keyName) { flags.insert(.maskSecondaryFn) }
        if ["left", "right", "up", "down"].contains(keyName) { flags.insert(.maskNumericPad) }
        post(code: code, flags: flags, text: nil)
    }

    /// Types text into whatever has the keys, one key at a time.
    static func type(_ text: String) {
        for ch in text {
            let lower = String(ch).lowercased()
            var flags: CGEventFlags = []
            var code: CGKeyCode = 0
            if ch == " " {
                code = codes["space"]!
            } else if let base = shifted[ch], let c = codes[base] {
                code = c; flags.insert(.maskShift)
            } else if let c = codes[lower] {
                code = c
                if String(ch) != lower { flags.insert(.maskShift) }
            }
            post(code: code, flags: flags, text: String(ch))
            pause(0.02)
        }
    }

    private static func post(code: CGKeyCode, flags: CGEventFlags, text: String?) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.post(tap: .cghidEventTap)
            pause(0.012)
        }
        pause(0.03)
    }

    static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        pause(0.05)
    }

    static func click(_ point: CGPoint, count: Int = 1, right: Bool = false) {
        move(to: point)
        let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = right ? .right : .left
        for n in 1...max(1, count) {
            for type in [downType, upType] {
                guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                else { continue }
                event.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                event.post(tap: .cghidEventTap)
                pause(0.02)
            }
            pause(0.05)
        }
        pause(0.1)
    }

    /// Waits while letting the run loop deliver notifications.
    static func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
