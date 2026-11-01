import Foundation

/// A global shortcut for the launcher: a virtual key code and Carbon's
/// modifier mask, as RegisterEventHotKey takes them.
public struct LauncherHotkey: Sendable, Equatable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon's modifier bits (cmdKey, shiftKey, optionKey, controlKey).
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public static let space: UInt32 = 49
    public static let commandSpace = LauncherHotkey(keyCode: space, modifiers: command)

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & (Self.command | Self.shift | Self.option | Self.control)
    }

    /// A global shortcut needs Command, Option or Control; Shift alone would take a letter from typing.
    public var isUsable: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0 || Self.functionKeys[keyCode] != nil
    }

    /// "⌃⌥⌘Space", in macOS's modifier order.
    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// The key's name on an ANSI keyboard.
    public static func keyName(_ code: UInt32) -> String {
        if let name = names[code] { return name }
        if let name = functionKeys[code] { return name }
        return "Key \(code)"
    }

    static let names: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape", 50: "`", 27: "-", 24: "=",
        33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static let functionKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// Stored as two numbers in a dictionary.
    public var defaultsValue: [String: Int] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers)] }

    public init?(defaultsValue: Any?) {
        guard let dict = defaultsValue as? [String: Any],
              let code = (dict["keyCode"] as? NSNumber)?.uint32Value,
              let modifiers = (dict["modifiers"] as? NSNumber)?.uint32Value else { return nil }
        self.init(keyCode: code, modifiers: modifiers)
    }
}

/// Whether Sight takes Command+Space, and the shortcut it registers. Setup sets
/// TakesCommandSpace when it turns Spotlight's shortcut off, then restarts
/// Sight. A shortcut recorded in Settings (`LauncherHotkey`) replaces it.
public enum HotkeySetting {
    public static let suiteName = "com.grandline.sight"
    public static let key = "TakesCommandSpace"
    /// A recorded shortcut: {keyCode, modifiers}.
    public static let hotkeyKey = "LauncherHotkey"

    /// Reads Sight's defaults: `.standard` inside Sight, its suite elsewhere.
    public static func takesCommandSpace(_ defaults: UserDefaults? = nil) -> Bool {
        (defaults ?? sightDefaults).bool(forKey: key)
    }

    /// The shortcut to register: the recorded one, else Command+Space once
    /// setup has handed it over, else none.
    public static func hotkey(_ defaults: UserDefaults? = nil) -> LauncherHotkey? {
        let store = defaults ?? sightDefaults
        if let recorded = LauncherHotkey(defaultsValue: store.object(forKey: hotkeyKey)) { return recorded }
        return takesCommandSpace(store) ? .commandSpace : nil
    }

    /// The shortcut `setHotkey(hotkey)` would make current, without saving it:
    /// what to register first, before anything is saved.
    public static func resolved(_ hotkey: LauncherHotkey?, _ defaults: UserDefaults? = nil) -> LauncherHotkey? {
        if let hotkey { return hotkey }
        return takesCommandSpace(defaults ?? sightDefaults) ? .commandSpace : nil
    }

    /// nil goes back to the default (Command+Space when setup handed it over).
    public static func setHotkey(_ hotkey: LauncherHotkey?, _ defaults: UserDefaults? = nil) {
        let store = defaults ?? sightDefaults
        if let hotkey { store.set(hotkey.defaultsValue, forKey: hotkeyKey) } else { store.removeObject(forKey: hotkeyKey) }
    }

    /// A suite named after the running app's own bundle ID reads nothing, so Sight uses `.standard`.
    static var sightDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}

/// The registered launcher shortcut. A new one is registered while the old
/// one is still held, and the old one goes only once the new one took: a
/// shortcut macOS refuses leaves the old one working.
public struct HotkeyRegistration<Handle> {
    public private(set) var shortcut: LauncherHotkey?
    public private(set) var handle: Handle?

    public init() {}

    /// Makes `new` the shortcut. Returns false, keeping the current one, when
    /// `register` refuses it (another app or Spotlight holds it).
    public mutating func change(to new: LauncherHotkey?, register: (LauncherHotkey) -> Handle?) -> Bool {
        guard let new else {
            handle = nil
            shortcut = nil
            return true
        }
        if new == shortcut, handle != nil { return true }
        guard let fresh = register(new) else { return false }
        handle = fresh
        shortcut = new
        return true
    }

    /// Lets the shortcut go while a new one is recorded (it must reach the field).
    public mutating func suspend() {
        handle = nil
        shortcut = nil
    }
}
