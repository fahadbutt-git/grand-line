import Foundation

/// What a search sends to the window as its providers answer.
public enum SearchUpdate: Sendable, Equatable {
    /// The instant providers' results, grouped. Replaces the list.
    case replace([ResultGroup], limitScale: Int)
    /// A slower provider's results, ranked. Merged below the selection.
    case merge([LaunchResult])
    /// Every provider has answered.
    case finished(milliseconds: Int)
}
