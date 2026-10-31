import Foundation

/// Whether Sight takes Command+Space. Setup sets TakesCommandSpace when it turns
/// Spotlight's shortcut off, then restarts Sight, so this is read once at launch.
public enum HotkeySetting {
    public static let suiteName = "com.grandline.sight"
    public static let key = "TakesCommandSpace"

    /// Reads Sight's defaults: `.standard` inside Sight, its suite elsewhere.
    public static func takesCommandSpace(_ defaults: UserDefaults? = nil) -> Bool {
        (defaults ?? sightDefaults).bool(forKey: key)
    }

    /// A suite named after the running app's own bundle ID reads nothing, so Sight uses `.standard`.
    static var sightDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
