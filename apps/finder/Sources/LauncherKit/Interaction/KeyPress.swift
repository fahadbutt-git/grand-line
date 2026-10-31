import Foundation

/// A key event without AppKit types, so the key rules can be tested.
public struct KeyPress: Sendable, Equatable {
    public var keyCode: UInt16
    /// The characters ignoring modifiers, lowercased ("k", "1").
    public var characters: String
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(keyCode: UInt16, characters: String = "", command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// Virtual key codes from Carbon's Events.h.
    public enum Code {
        public static let returnKey: UInt16 = 36
        public static let enter: UInt16 = 76
        public static let tab: UInt16 = 48
        public static let escape: UInt16 = 53
        public static let up: UInt16 = 126
        public static let down: UInt16 = 125
        public static let pageUp: UInt16 = 116
        public static let pageDown: UInt16 = 121
        public static let space: UInt16 = 49
    }
}
