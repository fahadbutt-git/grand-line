import Foundation

/// A keyboard shortcut, as iceberg.toml writes it: modifier names and a key
/// joined with `+`, such as `"ctrl+option+cmd+n"`. The key codes are the
/// positions on a US keyboard (macOS virtual key codes), which is what a
/// global shortcut is registered with.
public struct KeyShortcut: Equatable, Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    /// The key's name, lower case ("n", "f5", "space").
    public var key: String
    public var keyCode: UInt16
    public var modifiers: Modifiers

    /// Opens or closes the panel. The same keys as the Caps Lock layer's
    /// shortcut for the panel, with Command in place of Caps Lock.
    public static let defaultToggle = KeyShortcut(key: "n", keyCode: 45, modifiers: [.control, .option, .command])

    public init(key: String, keyCode: UInt16, modifiers: Modifiers) {
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a key press. Nil for a key without a name here, or with no
    /// modifier other than Shift (a plain letter cannot be a global shortcut).
    public init?(keyCode: UInt16, modifiers: Modifiers) {
        guard let name = Self.name(forKeyCode: keyCode) else { return nil }
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else { return nil }
        self.init(key: name, keyCode: keyCode, modifiers: modifiers)
    }

    /// Reads `"ctrl+option+cmd+n"`, `"Control+Alt+Command+N"` or `"⌃⌥⌘N"`.
    public static func parse(_ text: String) -> KeyShortcut? {
        var rest = text.trimmingCharacters(in: .whitespaces).lowercased()
        var modifiers: Modifiers = []
        // Symbols first: ⌃⌥⇧⌘ before the key, with or without "+".
        let symbols: [Character: Modifiers] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]
        while let first = rest.first, let m = symbols[first] {
            modifiers.insert(m)
            rest.removeFirst()
            if rest.first == "+" { rest.removeFirst() }
        }
        var parts = rest.split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // "ctrl++" is Control and the plus key, which has no name here.
        guard let keyName = parts.popLast(), !keyName.isEmpty else { return nil }
        for part in parts {
            switch part {
            case "ctrl", "control", "ctl": modifiers.insert(.control)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "cmd", "command", "super", "meta": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        let key = keyAliases[keyName] ?? keyName
        guard let code = keyCodes[key] else { return nil }
        return KeyShortcut(keyCode: code, modifiers: modifiers)
    }

    /// How iceberg.toml writes it: `"ctrl+option+cmd+n"`.
    public var text: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }

    /// How menus show it: `⌃⌥⌘N`.
    public var symbols: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        let shown: String
        switch key {
        case "space": shown = "Space"
        case "return": shown = "↩"
        case "tab": shown = "⇥"
        case "escape": shown = "⎋"
        case "delete": shown = "⌫"
        case "left": shown = "←"
        case "right": shown = "→"
        case "up": shown = "↑"
        case "down": shown = "↓"
        default: shown = key.uppercased()
        }
        return out + shown
    }

    public var description: String { text }

    /// The modifier bits Carbon's RegisterEventHotKey takes
    /// (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonModifiers: UInt32 {
        var bits: UInt32 = 0
        if modifiers.contains(.command) { bits |= 1 << 8 }
        if modifiers.contains(.shift) { bits |= 1 << 9 }
        if modifiers.contains(.option) { bits |= 1 << 11 }
        if modifiers.contains(.control) { bits |= 1 << 12 }
        return bits
    }

    public static func name(forKeyCode code: UInt16) -> String? {
        names[code]
    }

    static let keyAliases: [String: String] = [
        "enter": "return", "esc": "escape", "backspace": "delete", "spacebar": "space",
        "pgup": "pageup", "pgdn": "pagedown", "arrowleft": "left", "arrowright": "right",
        "arrowup": "up", "arrowdown": "down",
    ]

    /// macOS virtual key codes (kVK_ANSI_* and friends).
    static let keyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51,
        "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    static let names: [UInt16: String] = {
        var out: [UInt16: String] = [:]
        for (name, code) in keyCodes { out[code] = name }
        return out
    }()
}
