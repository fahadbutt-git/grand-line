import Foundation

/// Whether Byakugan takes Command+Space. Setup sets TakesCommandSpace when it turns
/// Spotlight's shortcut off, then restarts Byakugan, so this is read once at launch.
public enum HotkeySetting {
    public static let suiteName = "com.grandline.byakugan"
    public static let key = "TakesCommandSpace"

    /// Reads Byakugan's defaults: `.standard` inside Byakugan, its suite elsewhere.
    public static func takesCommandSpace(_ defaults: UserDefaults? = nil) -> Bool {
        (defaults ?? byakuganDefaults).bool(forKey: key)
    }

    /// A suite named after the running app's own bundle ID reads nothing, so Byakugan uses `.standard`.
    static var byakuganDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}
