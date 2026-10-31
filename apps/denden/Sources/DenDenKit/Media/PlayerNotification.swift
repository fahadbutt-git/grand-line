import Foundation

/// The fallback when mediaremote-adapter cannot run: Spotify and Music both
/// post a distributed notification on every change of track or state
/// (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`).
/// This turns one into a full Now Playing payload. No artwork comes this way.
public enum PlayerNotification {
    public static let spotify = "com.spotify.client.PlaybackStateChanged"
    public static let music = "com.apple.Music.playerInfo"

    public static func bundleIdentifier(forNotification name: String) -> String? {
        switch name {
        case spotify: return "com.spotify.client"
        case music: return "com.apple.Music"
        default: return nil
        }
    }

    public static func payload(bundleIdentifier: String, info: [String: Any]) -> [String: JSONValue] {
        let state = (info["Player State"] as? String) ?? ""
        if state == "Stopped" { return [:] }
        var p: [String: JSONValue] = [
            "bundleIdentifier": .string(bundleIdentifier),
            "playing": .bool(state == "Playing"),
        ]
        if let s = info["Name"] as? String { p["title"] = .string(s) }
        if let s = info["Artist"] as? String { p["artist"] = .string(s) }
        if let s = info["Album"] as? String { p["album"] = .string(s) }
        // Spotify gives "Duration" in ms; Music gives "Total Time" in ms.
        if let ms = number(info["Duration"]) ?? number(info["Total Time"]), ms > 0 { p["duration"] = .number(ms / 1000) }
        if let s = number(info["Playback Position"]) {
            p["elapsedTime"] = .number(s)
            p["timestamp"] = .number(Date().timeIntervalSince1970)
        }
        return p
    }

    static func number(_ v: Any?) -> Double? {
        switch v {
        case let i as Int: return Double(i)
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}
