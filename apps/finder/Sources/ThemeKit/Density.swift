import Foundation

/// How tightly rows are packed. A theme may set it with UI_DENSITY; no theme
/// in the package does, so each app keeps its own choice in its defaults
/// under `Density`.
public enum Density: String, Sendable, CaseIterable {
    case compact
    case regular
    case comfortable

    /// The key in each app's defaults domain.
    public static let defaultsKey = "Density"
    /// The optional theme key.
    public static let themeKey = "UI_DENSITY"

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .comfortable: return "Comfortable"
        }
    }

    /// A row height or padding sized for this density, from its regular size.
    public func scaled(_ regular: Double) -> Double {
        switch self {
        case .compact: return (regular * 0.84).rounded()
        case .regular: return regular
        case .comfortable: return (regular * 1.2).rounded()
        }
    }

    /// The theme's density, else the app's stored choice, else regular.
    public static func current(theme: Theme?, defaults: UserDefaults) -> Density {
        if let own = theme?.density { return own }
        return defaults.string(forKey: defaultsKey).flatMap(Density.init(rawValue:)) ?? .regular
    }
}
