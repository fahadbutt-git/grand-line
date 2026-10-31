import Foundation

/// Back and forward (Cmd+[ and Cmd+]) for one pane.
public struct NavigationHistory: Equatable, Sendable {
    public private(set) var current: BrowserLocation
    public private(set) var backStack: [BrowserLocation] = []
    public private(set) var forwardStack: [BrowserLocation] = []
    public static let limit = 100

    public init(_ start: BrowserLocation) {
        current = start
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    /// Going somewhere new clears Forward. Going to where you are does nothing.
    public mutating func visit(_ location: BrowserLocation) {
        guard location != current else { return }
        backStack.append(current)
        if backStack.count > Self.limit { backStack.removeFirst(backStack.count - Self.limit) }
        forwardStack.removeAll()
        current = location
    }

    @discardableResult
    public mutating func back() -> BrowserLocation? {
        guard let previous = backStack.popLast() else { return nil }
        forwardStack.append(current)
        current = previous
        return previous
    }

    @discardableResult
    public mutating func forward() -> BrowserLocation? {
        guard let next = forwardStack.popLast() else { return nil }
        backStack.append(current)
        current = next
        return next
    }

    /// Replaces the current place without a history entry, as when a folder is
    /// renamed while shown.
    public mutating func replaceCurrent(_ location: BrowserLocation) {
        current = location
    }
}
