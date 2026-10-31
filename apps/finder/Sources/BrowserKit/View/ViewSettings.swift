import Foundation

/// How a folder is shown.
public struct ViewSettings: Codable, Hashable, Sendable {
    public var mode: ViewMode
    public var sort: ItemSort
    /// Icon and gallery thumbnail edge, in points.
    public var iconSize: Double

    public init(mode: ViewMode = .list, sort: ItemSort = ItemSort(), iconSize: Double = 64) {
        self.mode = mode
        self.sort = sort
        self.iconSize = iconSize
    }

    public static let iconSizes: ClosedRange<Double> = 32...256
}

/// One view setting everywhere, with exceptions for single folders (R6). The
/// app keeps them in its own file and never writes .DS_Store.
public struct ViewPreferences: Codable, Equatable, Sendable {
    public var defaults: ViewSettings
    /// Folder path to its own settings.
    public var exceptions: [String: ViewSettings]
    /// Folder path to its manual order of names (R7).
    public var manualOrders: [String: [String]]

    public init(defaults: ViewSettings = ViewSettings(), exceptions: [String: ViewSettings] = [:], manualOrders: [String: [String]] = [:]) {
        self.defaults = defaults
        self.exceptions = exceptions
        self.manualOrders = manualOrders
    }

    /// A folder with an exception uses it; any other folder uses the window's setting.
    public func settings(for folder: String, window: ViewSettings) -> ViewSettings {
        exceptions[Self.key(folder)] ?? window
    }

    public func hasException(_ folder: String) -> Bool {
        exceptions[Self.key(folder)] != nil
    }

    /// A change made in a folder: updates its exception if it has one, otherwise
    /// it is a window change and nothing is stored here. Returns whether it was stored.
    @discardableResult
    public mutating func change(_ settings: ViewSettings, in folder: String) -> Bool {
        let key = Self.key(folder)
        guard exceptions[key] != nil else { return false }
        exceptions[key] = settings
        return true
    }

    public mutating func remember(_ settings: ViewSettings, for folder: String) {
        exceptions[Self.key(folder)] = settings
    }

    public mutating func forget(_ folder: String) {
        exceptions[Self.key(folder)] = nil
    }

    public func manualOrder(for folder: String) -> [String] {
        manualOrders[Self.key(folder)] ?? []
    }

    public mutating func setManualOrder(_ names: [String], for folder: String) {
        manualOrders[Self.key(folder)] = names.isEmpty ? nil : names
    }

    static func key(_ folder: String) -> String {
        let standard = (folder as NSString).standardizingPath
        return standard.isEmpty ? "/" : standard
    }
}
