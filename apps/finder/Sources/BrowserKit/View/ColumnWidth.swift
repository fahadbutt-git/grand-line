import Foundation

/// Name columns sized to the longest name (R7), so nothing is cut short until
/// the column would pass `maximum`; after that names truncate with an ellipsis.
public enum ColumnWidth {
    /// Icon, gaps and the disclosure chevron around the name.
    public static let chrome: Double = 52
    public static let minimum: Double = 160
    public static let maximum: Double = 560

    /// `measure` returns a name's width in points in the row font.
    public static func fitting(_ names: [String], measure: (String) -> Double) -> Double {
        let widest = names.reduce(0.0) { max($0, measure($1)) }
        return min(maximum, max(minimum, (widest + chrome).rounded(.up)))
    }
}
