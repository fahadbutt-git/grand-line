import AppKit
import Foundation
import IcebergKit

/// Play, pause, next and previous for whatever is playing.
///
/// Sending commands to MediaRemote still works from any app (only reading
/// was restricted in macOS 15.4), so commands go in-process the way Boring
/// Notch sends them. When that symbol is missing, the adapter sends them, and
/// as a last resort Spotify and Music are told directly with AppleScript.
enum MediaCommand: Int {
    case play = 0, pause = 1, toggle = 2, next = 4, previous = 5

    var appleScriptVerb: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .toggle: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        }
    }
}

enum MediaRemote {
    /// `Boolean MRMediaRemoteSendCommand(MRMediaRemoteCommand, CFDictionaryRef)`.
    private typealias SendCommand = @convention(c) (UInt32, UnsafeRawPointer?) -> UInt8

    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    /// False when the command could not be sent this way.
    static func send(_ command: MediaCommand) -> Bool {
        guard let sendCommand else { return false }
        // The result says little (it is false for some players that obey), so
        // it is not used to decide on a second route, which would toggle twice.
        _ = sendCommand(UInt32(command.rawValue), nil)
        return true
    }

    /// Tells Spotify or Music directly (needs Automation permission once).
    static func sendWithAppleScript(_ command: MediaCommand, bundleIdentifier: String?) {
        let app: String
        switch bundleIdentifier {
        case "com.spotify.client": app = "Spotify"
        case "com.apple.Music": app = "Music"
        default:
            if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty { app = "Spotify" }
            else { app = "Music" }
        }
        let source = "with timeout of 2 seconds\ntell application \"\(app)\" to \(command.appleScriptVerb)\nend timeout"
        // Off the main thread, with a time limit: a busy player must not
        // freeze the panel (AppleScriptCall).
        DispatchQueue.global(qos: .userInitiated).async {
            _ = AppleScriptCall.run(source)
        }
    }
}
