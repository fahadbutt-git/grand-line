import Foundation

/// A key and its modifiers, as a menu shows it and as a key press arrives.
public struct Shortcut: Hashable, Codable, Sendable, CustomStringConvertible {
    public enum Key: Hashable, Codable, Sendable {
        /// A printable key, lowercased: "n", "1", ".", "[".
        case character(String)
        case returnKey
        case delete
        case space
        case tab
        case escape
        case up
        case down
        case left
        case right
        /// F1 to F12.
        case function(Int)
    }

    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        if case .character(let text) = key {
            self.key = .character(text.lowercased())
        } else {
            self.key = key
        }
        self.modifiers = modifiers
    }

    public static func command(_ character: String, _ extra: Modifiers = []) -> Shortcut {
        Shortcut(.character(character), extra.union(.command))
    }

    /// Apple's order: Control, Option, Shift, Command, then the key: "⌃⌥⌘1".
    public var description: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    public var keyLabel: String {
        switch key {
        case .character(let text): return text.uppercased()
        case .returnKey: return "↩"
        case .delete: return "⌫"
        case .space: return "Space"
        case .tab: return "Tab"
        case .escape: return "Esc"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .function(let n): return "F\(n)"
        }
    }

    /// NSMenuItem.keyEquivalent: arrows and function keys use AppKit's private-use
    /// characters (NSUpArrowFunctionKey is U+F700, NSF1FunctionKey is U+F704).
    public var menuKeyEquivalent: String {
        switch key {
        case .character(let text): return text
        case .returnKey: return "\r"
        case .delete: return "\u{8}"
        case .space: return " "
        case .tab: return "\t"
        case .escape: return "\u{1b}"
        case .up: return Self.privateUse(0xF700)
        case .down: return Self.privateUse(0xF701)
        case .left: return Self.privateUse(0xF702)
        case .right: return Self.privateUse(0xF703)
        case .function(let n): return Self.privateUse(0xF703 + UInt32(max(1, min(n, 35))))
        }
    }

    /// Keys without Command or Control (Return, Space, Tab, F2). Their menu items
    /// are disabled while a text field is being edited, so typing is never taken.
    public var isPlain: Bool {
        !modifiers.contains(.command) && !modifiers.contains(.control)
    }

    static func privateUse(_ value: UInt32) -> String {
        UnicodeScalar(value).map { String(Character($0)) } ?? ""
    }

    /// A key press from its macOS virtual key code and its characters without
    /// modifiers, for the keys the file list handles itself.
    public static func from(keyCode: UInt16, characters: String, modifiers: Modifiers) -> Shortcut? {
        let special: [UInt16: Key] = [
            36: .returnKey, 76: .returnKey, 51: .delete, 117: .delete, 49: .space, 48: .tab, 53: .escape,
            126: .up, 125: .down, 123: .left, 124: .right,
            122: .function(1), 120: .function(2), 99: .function(3), 118: .function(4), 96: .function(5),
            97: .function(6), 98: .function(7), 100: .function(8), 101: .function(9), 109: .function(10),
            103: .function(11), 111: .function(12),
        ]
        if let key = special[keyCode] { return Shortcut(key, modifiers) }
        guard let first = characters.first else { return nil }
        return Shortcut(.character(String(first)), modifiers)
    }
}
