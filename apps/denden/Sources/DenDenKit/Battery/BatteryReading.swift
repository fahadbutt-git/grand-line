import Foundation

/// The internal battery, read from one IOKit power source description
/// (`IOPSGetPowerSourceDescription`). Keys are IOKit's own strings, so this
/// parses without IOKit and the tests can feed it dictionaries.
public struct BatteryReading: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var isCharged: Bool
    /// Minutes to empty or to full, when macOS has worked it out.
    public var minutesRemaining: Int?

    public init(percent: Int, isCharging: Bool = false, isPluggedIn: Bool = false,
                isCharged: Bool = false, minutesRemaining: Int? = nil) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.isCharged = isCharged
        self.minutesRemaining = minutesRemaining
    }

    /// nil for anything that is not the internal battery (a UPS, a mouse).
    public static func parse(_ d: [String: Any]) -> BatteryReading? {
        if let type = d["Type"] as? String, type != "InternalBattery" { return nil }
        if let present = d["Is Present"] as? Bool, !present { return nil }
        guard let current = number(d["Current Capacity"]), let max = number(d["Max Capacity"]), max > 0 else { return nil }
        let percent = Int((current / max * 100).rounded())
        let plugged = (d["Power Source State"] as? String) == "AC Power"
        let charging = (d["Is Charging"] as? Bool) ?? false
        let charged = (d["Is Charged"] as? Bool) ?? false
        let minutesKey = charging ? "Time to Full Charge" : "Time to Empty"
        var minutes = number(d[minutesKey]).map { Int($0) }
        if let m = minutes, m <= 0 || (plugged && !charging) { minutes = nil }
        return BatteryReading(percent: Swift.max(0, Swift.min(100, percent)), isCharging: charging,
                              isPluggedIn: plugged, isCharged: charged, minutesRemaining: minutes)
    }

    static func number(_ v: Any?) -> Double? {
        switch v {
        case let i as Int: return Double(i)
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    /// The SF Symbol for this state.
    public var symbol: String {
        if isCharging || (isPluggedIn && !isCharged && percent < 100) { return "battery.100percent.bolt" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// True when the level deserves a warning colour.
    public var isLow: Bool { !isPluggedIn && percent <= 15 }

    /// "82%", "82%, 3:10 left", "82%, charging, full in 0:45".
    public var summary: String {
        var parts = ["\(percent)%"]
        if isCharging {
            parts.append("charging")
            if let m = minutesRemaining { parts.append("full in \(Self.clock(m))") }
        } else if isPluggedIn {
            parts.append(isCharged || percent >= 100 ? "charged" : "on power")
        } else if let m = minutesRemaining {
            parts.append("\(Self.clock(m)) left")
        }
        return parts.joined(separator: ", ")
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
