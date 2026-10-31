import Foundation

/// The order of the result sections and how many rows each shows, as set in
/// Sight's Settings (Sources for the order, Search for the counts). The window
/// reads `current` when it starts a list; tests pass their own.
public struct ResultLayout: Sendable, Equatable {
    /// Every section, in display order.
    public var order: [ResultSection]
    /// Rows per section where it differs from `ResultSection.limit`.
    public var limits: [ResultSection: Int]

    public init(order: [ResultSection] = ResultSection.allCases, limits: [ResultSection: Int] = [:]) {
        var seen = Set<ResultSection>()
        var full = order.filter { seen.insert($0).inserted }
        for section in ResultSection.allCases where !seen.contains(section) { full.append(section) }
        self.order = full
        self.limits = limits.filter { $0.value != $0.key.limit }
    }

    public static let standard = ResultLayout()

    /// The sections whose row count can be changed (the top hit is always one row).
    public static let adjustable: [ResultSection] = ResultSection.allCases.filter { $0 != .topHit }
    public static let limitRange: ClosedRange<Int> = 1...20

    public func limit(_ section: ResultSection) -> Int {
        guard section != .topHit else { return 1 }
        return limits[section] ?? section.limit
    }

    /// The section's place; lower shows higher.
    public func rank(_ section: ResultSection) -> Int {
        order.firstIndex(of: section) ?? (order.count + section.rawValue)
    }

    public func comesBefore(_ a: ResultSection, _ b: ResultSection) -> Bool {
        rank(a) < rank(b)
    }

    // MARK: The layout in use

    private static let lock = NSLock()
    private static var shared = ResultLayout.standard

    public static var current: ResultLayout {
        get { lock.withLock { shared } }
        set { lock.withLock { shared = newValue } }
    }
}
