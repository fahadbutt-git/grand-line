import Foundation

/// The home folder Nexus works in. One answer for every part of the app: the
/// path bar's `~`, Go to Folder, the sidebar, settings and state files.
///
/// `CFFIXED_USER_HOME` comes first, as it does for NSHomeDirectory(): the user
/// journeys run the app with a fixture home this way, and a home worked out from
/// the user database (getpwuid) would point at the real one instead.
public enum HomeFolder {
    public static var url: URL { url(environment: ProcessInfo.processInfo.environment) }

    public static var path: String { url.path }

    /// The home folder for this environment. Testable form of `url`.
    public static func url(environment: [String: String], fallback: () -> String = { NSHomeDirectory() }) -> URL {
        if let fixed = environment["CFFIXED_USER_HOME"], fixed.hasPrefix("/") {
            return URL(fileURLWithPath: fixed, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: fallback(), isDirectory: true).standardizedFileURL
    }
}
