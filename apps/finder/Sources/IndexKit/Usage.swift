import Foundation

/// How often and how lately a path was opened. Breaks ties between equal matches.
struct Usage: Codable, Sendable, Equatable {
    var count: Int
    var last: Date

    /// More opens count for less each time; a recent open counts for more.
    func score(now: Date) -> Float {
        let age = now.timeIntervalSince(last)
        let recency: Float
        switch age {
        case ..<3_600: recency = 4
        case ..<86_400: recency = 3
        case ..<604_800: recency = 2
        case ..<2_592_000: recency = 1
        default: recency = 0
        }
        return Float(log2(Double(count) + 1)) + recency
    }
}
