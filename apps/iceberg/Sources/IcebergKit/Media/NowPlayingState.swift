import Foundation

/// What is playing, as told by mediaremote-adapter's `stream` command.
///
/// Each stream line is `{"type":"data","diff":true|false,"payload":{...}}`.
/// A full payload (`diff` false) replaces everything; a diff payload changes
/// only the keys it names, and a key set to null is removed. An empty full
/// payload means nothing is playing.
public struct NowPlayingState: Equatable, Sendable {
    public private(set) var fields: [String: JSONValue] = [:]

    public init(fields: [String: JSONValue] = [:]) { self.fields = fields }

    public var title: String? { nonEmpty(fields["title"]?.stringValue) }
    public var artist: String? { nonEmpty(fields["artist"]?.stringValue) }
    public var album: String? { nonEmpty(fields["album"]?.stringValue) }
    public var isPlaying: Bool { fields["playing"]?.boolValue ?? false }
    public var duration: TimeInterval? { fields["duration"]?.doubleValue }
    public var elapsed: TimeInterval? { fields["elapsedTime"]?.doubleValue }
    public var playbackRate: Double { fields["playbackRate"]?.doubleValue ?? (isPlaying ? 1 : 0) }
    /// The app to show and control: the parent app for web players.
    public var bundleIdentifier: String? {
        nonEmpty(fields["parentApplicationBundleIdentifier"]?.stringValue) ?? nonEmpty(fields["bundleIdentifier"]?.stringValue)
    }
    public var artworkBase64: String? { nonEmpty(fields["artworkData"]?.stringValue) }
    /// When `elapsed` was measured (an ISO date or seconds since 1970).
    public var timestamp: Date? {
        switch fields["timestamp"] {
        case .string(let s)?:
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        case .number(let n)?:
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1e6 : n)
        default:
            return nil
        }
    }

    /// True when something has a title to show.
    public var hasMedia: Bool { title != nil }

    /// The playback position at `now`, counting on from the last report.
    public func position(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var position = elapsed
        if isPlaying, let t = timestamp { position += max(0, now.timeIntervalSince(t)) * playbackRate }
        if let d = duration, d > 0 { position = min(position, d) }
        return position
    }

    /// Applies one stream line. Returns false (and changes nothing) for a line
    /// that is not a data update.
    @discardableResult
    public mutating func apply(line: String) -> Bool {
        guard let data = line.data(using: .utf8), let value = try? JSONValue.parse(data),
              let object = value.objectValue else { return false }
        if let type = object["type"]?.stringValue, type != "data" { return false }
        guard let payload = object["payload"]?.objectValue else {
            if case .null? = object["payload"] { fields = [:]; return true }
            return false
        }
        let diff = object["diff"]?.boolValue ?? false
        apply(payload: payload, diff: diff)
        return true
    }

    public mutating func apply(payload: [String: JSONValue], diff: Bool) {
        if !diff {
            fields = payload.filter { $0.value != .null }
            return
        }
        for (key, value) in payload {
            if value == .null { fields.removeValue(forKey: key) } else { fields[key] = value }
        }
    }

    /// True when the artwork differs from `other`'s, so the image is decoded
    /// again only when it changed.
    public func artworkDiffers(from other: NowPlayingState) -> Bool {
        fields["artworkData"] != other.fields["artworkData"]
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }
}

/// Splits a byte stream into lines, keeping any partial line for the next chunk.
///
/// A line longer than `maxLineBytes` is dropped whole: once it overflows,
/// everything up to its newline is thrown away, so its tail never comes out
/// as a line of its own.
public struct LineBuffer: Sendable {
    private var pending = Data()
    /// True while throwing away the rest of an overlong line.
    private var discarding = false
    /// Lines longer than this are dropped (artwork lines are a few hundred KB).
    public var maxLineBytes = 16 * 1024 * 1024

    public init() {}

    public mutating func append(_ chunk: Data) -> [String] {
        var lines: [String] = []
        var rest = chunk[chunk.startIndex...]
        if discarding {
            guard let newline = rest.firstIndex(of: 0x0A) else { return [] }
            discarding = false
            rest = rest[rest.index(after: newline)...]
        }
        pending.append(contentsOf: rest)
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            let tooLong = lineData.count > maxLineBytes
            pending.removeSubrange(pending.startIndex...newline)
            if !tooLong, let line = String(data: lineData, encoding: .utf8), !line.isEmpty { lines.append(line) }
        }
        if pending.count > maxLineBytes {
            pending.removeAll()
            discarding = true
        }
        return lines
    }
}
