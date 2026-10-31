import Foundation

/// A key with modifiers, shown as macOS draws it: ⌃⌥⇧⌘K.
public struct KeyShortcut: Codable, Hashable, Sendable {
    public var key: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(_ key: String, command: Bool = true, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    public var label: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + key.uppercased()
    }

    /// Reads "⇧⌘C", "Shift+Command+C" or "cmd + shift + c". Without a modifier
    /// it is a plain key. nil for text with an unknown word or no key.
    public init?(parsing text: String) {
        var key: String?
        var command = false, shift = false, option = false, control = false
        var words: [String] = []
        for part in text.split(whereSeparator: { $0 == "+" || $0 == " " }) {
            var rest = Substring(part)
            while let symbol = rest.first, "⌘⇧⌥⌃".contains(symbol) {
                words.append(String(symbol))
                rest = rest.dropFirst()
            }
            if !rest.isEmpty { words.append(String(rest)) }
        }
        for word in words {
            switch word.lowercased() {
            case "⌘", "cmd", "command": command = true
            case "⇧", "shift": shift = true
            case "⌥", "opt", "option", "alt": option = true
            case "⌃", "ctrl", "control": control = true
            default:
                guard key == nil, VirtualKey.code(for: word) != nil else { return nil }
                key = word.lowercased()
            }
        }
        guard let key else { return nil }
        self.init(key, command: command, shift: shift, option: option, control: control)
    }

    /// The key's virtual key code, for posting it as a key event.
    public var virtualKey: UInt16? { VirtualKey.code(for: key) }

    /// The modifier bits of an Accessibility menu item (AXMenuItemCmdModifiers):
    /// 1 shift, 2 option, 4 control, 8 no command.
    public init(menuKey: String, axModifiers: Int) {
        self.init(
            menuKey,
            command: axModifiers & 8 == 0,
            shift: axModifiers & 1 != 0,
            option: axModifiers & 2 != 0,
            control: axModifiers & 4 != 0
        )
    }
}
