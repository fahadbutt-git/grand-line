import Foundation

/// Typing a name selects the first item that starts with it, as in Finder.
/// Keys typed within `pause` seconds of each other build one prefix.
public struct TypeSelect: Sendable {
    public static let pause: TimeInterval = 1.0
    private var typed = ""
    private var last = Date.distantPast

    public init() {}

    /// Returns the index of the item to select, or nil when none matches.
    public mutating func type(_ text: String, names: [String], at now: Date = Date()) -> Int? {
        if now.timeIntervalSince(last) > Self.pause { typed = "" }
        typed += text.lowercased()
        last = now
        let prefix = typed
        return names.firstIndex { $0.lowercased().hasPrefix(prefix) }
    }
}
