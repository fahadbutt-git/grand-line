import Foundation

/// What a HUD in the notch shows: a symbol in the left wing, and a level
/// bar or a short text in the right one.
public struct HUDEvent: Equatable, Sendable {
    public enum Kind: String, Sendable, Equatable { case volume, brightness, battery, device }
    /// How the symbol is coloured, as theme colours.
    public enum Tone: String, Sendable, Equatable { case normal, good, warning, critical }

    public var kind: Kind
    public var symbol: String
    /// 0 to 1, drawn as a bar; nil for a text-only HUD.
    public var level: Double?
    /// Beside the bar ("62%"), or alone ("Charging").
    public var text: String
    /// For VoiceOver and the tooltip: "Volume 62%".
    public var label: String
    public var tone: Tone

    public init(kind: Kind, symbol: String, level: Double?, text: String, label: String, tone: Tone = .normal) {
        self.kind = kind
        self.symbol = symbol
        self.level = level.map { min(max($0, 0), 1) }
        self.text = text
        self.label = label
        self.tone = tone
    }

    /// How long a HUD stays, in seconds; a new one in that time replaces it
    /// and starts the wait again.
    public static let duration: TimeInterval = 1.6

    static func percent(_ level: Double) -> Int { Int((min(max(level, 0), 1) * 100).rounded()) }

    public static func volume(level: Double, muted: Bool) -> HUDEvent {
        let shown = muted ? 0 : level
        let symbol: String
        if muted || level <= 0.001 { symbol = "speaker.slash.fill" }
        else if level < 0.34 { symbol = "speaker.wave.1.fill" }
        else if level < 0.67 { symbol = "speaker.wave.2.fill" }
        else { symbol = "speaker.wave.3.fill" }
        let text = muted ? "Muted" : "\(percent(level))%"
        return HUDEvent(kind: .volume, symbol: symbol, level: shown, text: text,
                        label: muted ? "Volume muted" : "Volume \(percent(level))%")
    }

    public static func brightness(level: Double) -> HUDEvent {
        let symbol = level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        return HUDEvent(kind: .brightness, symbol: symbol, level: level, text: "\(percent(level))%",
                        label: "Brightness \(percent(level))%")
    }

    public static func battery(_ reading: BatteryReading, reason: BatteryHUDPolicy.Reason) -> HUDEvent {
        let pct = "\(reading.percent)%"
        switch reason {
        case .pluggedIn:
            let charging = reading.isCharging || (!reading.isCharged && reading.percent < 100)
            return HUDEvent(kind: .battery, symbol: "battery.100percent.bolt", level: nil, text: pct,
                            label: charging ? "Charging, \(pct)" : "On power, \(pct)", tone: .good)
        case .unplugged:
            return HUDEvent(kind: .battery, symbol: reading.symbol, level: nil, text: pct,
                            label: "On battery, \(pct)", tone: .normal)
        case .low:
            return HUDEvent(kind: .battery, symbol: "battery.25percent", level: nil, text: pct,
                            label: "Battery low, \(pct)", tone: .warning)
        case .critical:
            return HUDEvent(kind: .battery, symbol: "battery.0percent", level: nil, text: pct,
                            label: "Battery very low, \(pct)", tone: .critical)
        }
    }

    public static func device(name: String, battery: DeviceBattery?) -> HUDEvent {
        let symbol = DeviceSymbol.symbol(forName: name)
        if let battery, let lowest = battery.lowest {
            let detail = battery.summary.map { ", \($0)" } ?? ""
            return HUDEvent(kind: .device, symbol: symbol, level: nil, text: "\(lowest)%",
                            label: "\(name) connected\(detail)", tone: lowest <= 15 ? .warning : .normal)
        }
        return HUDEvent(kind: .device, symbol: symbol, level: nil, text: "On", label: "\(name) connected")
    }
}

/// When the battery deserves a HUD: power connected or removed, and the
/// level falling to 20% and then 10% on battery. A reading the same as
/// before, or the first one, shows nothing.
public enum BatteryHUDPolicy {
    public enum Reason: String, Equatable, Sendable { case pluggedIn, unplugged, low, critical }

    public static let lowLevel = 20
    public static let criticalLevel = 10

    public static func reason(previous: BatteryReading?, current: BatteryReading) -> Reason? {
        guard let previous else { return nil }
        if !previous.isPluggedIn && current.isPluggedIn { return .pluggedIn }
        if previous.isPluggedIn && !current.isPluggedIn { return .unplugged }
        guard !current.isPluggedIn else { return nil }
        if previous.percent > criticalLevel && current.percent <= criticalLevel { return .critical }
        if previous.percent > lowLevel && current.percent <= lowLevel { return .low }
        return nil
    }
}

/// When a volume reading deserves a HUD: macOS reports a change for each
/// channel, and once more for the same value, so only a real change shows.
/// The first reading (on start, or a new output device) shows nothing.
public enum VolumeHUDPolicy {
    public struct Reading: Equatable, Sendable {
        public var level: Double
        public var muted: Bool
        public init(level: Double, muted: Bool) {
            self.level = level
            self.muted = muted
        }
    }

    public static func shows(previous: Reading?, current: Reading) -> Bool {
        guard let previous else { return false }
        return previous.muted != current.muted || abs(previous.level - current.level) >= 0.005
    }
}

/// Battery levels of Bluetooth headphones, as macOS reports them (AirPods
/// give each bud and the case; others one level). 0 or out of range means
/// not known.
public struct DeviceBattery: Equatable, Sendable {
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var single: Int?

    public init(left: Int? = nil, right: Int? = nil, caseLevel: Int? = nil, single: Int? = nil) {
        func valid(_ v: Int?) -> Int? { v.flatMap { (1...100).contains($0) ? $0 : nil } }
        self.left = valid(left)
        self.right = valid(right)
        self.caseLevel = valid(caseLevel)
        self.single = valid(single)
    }

    public var isKnown: Bool { lowest != nil }

    /// The lowest of the buds (or the one level), which is what runs out first.
    public var lowest: Int? {
        let buds = [left, right].compactMap { $0 }
        if let low = buds.min() { return low }
        return single
    }

    /// "L 80%, R 75%, case 40%", or "60%".
    public var summary: String? {
        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if parts.isEmpty, let single { parts.append("\(single)%") }
        if let caseLevel { parts.append("case \(caseLevel)%") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// The SF Symbol for a pair of headphones, from the name macOS gives it.
public enum DeviceSymbol {
    public static func symbol(forName name: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    /// Headphone connections in the first moments after Iceberg starts
    /// listening are ones that were already there, not news.
    public static let startupQuiet: TimeInterval = 3

    public static func announces(connectedAt t: Date, listeningSince start: Date) -> Bool {
        t.timeIntervalSince(start) >= startupQuiet
    }
}

/// The volume, brightness and mute keys, as macOS sends them (a
/// system-defined event of subtype 8, whose data1 holds the key and its state).
public enum MediaKey: Int, Equatable, Sendable {
    case soundUp = 0
    case soundDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7

    public var isVolume: Bool { self == .soundUp || self == .soundDown || self == .mute }
    public var isBrightness: Bool { self == .brightnessUp || self == .brightnessDown }

    /// The key in `data1`, and whether it went down (and is a repeat), or
    /// nil for any other key.
    public static func decode(data1: Int) -> (key: MediaKey, down: Bool, isRepeat: Bool)? {
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0x0000_FFFF
        let state = (flags & 0xFF00) >> 8
        guard let key = MediaKey(rawValue: code) else { return nil }
        // 0xA: down, 0xB: up.
        guard state == 0xA || state == 0xB else { return nil }
        return (key, state == 0xA, (flags & 0x1) == 1)
    }

    /// data1 for a key, for tests and for posting one.
    public static func data1(_ key: MediaKey, down: Bool, isRepeat: Bool = false) -> Int {
        (key.rawValue << 16) | ((down ? 0xA : 0xB) << 8) | (isRepeat ? 1 : 0)
    }
}

/// The next volume or brightness level for a key press, on macOS's grid:
/// sixteen steps, or sixty-four with Option and Shift held.
public enum LevelStep {
    public static func next(_ current: Double, up: Bool, fine: Bool) -> Double {
        let steps = fine ? 64.0 : 16.0
        let position = (min(max(current, 0), 1) * steps)
        // Snap to the grid first, so a level between steps lands on one.
        let snapped = up ? (position + 1e-6).rounded(.down) + 1 : (position - 1e-6).rounded(.up) - 1
        return min(max(snapped / steps, 0), 1)
    }
}
