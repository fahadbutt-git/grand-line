import Foundation

/// The sidebar is at least Finder's size (R29): 14 pt text in 30 pt rows, and
/// resizable between `minimumWidth` and `maximumWidth`.
public enum SidebarMetrics {
    public static let fontSize: Double = 14
    public static let rowHeight: Double = 30
    public static let symbolWidth: Double = 20
    public static let defaultWidth: Double = 220
    public static let minimumWidth: Double = 170
    public static let maximumWidth: Double = 420

    /// A dragged divider position, kept inside the limits.
    public static func clamp(_ width: Double) -> Double {
        min(maximumWidth, max(minimumWidth, width.rounded()))
    }
}
