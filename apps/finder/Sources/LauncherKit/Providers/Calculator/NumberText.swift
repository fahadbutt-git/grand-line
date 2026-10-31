import Foundation

/// Numbers as answers show them: up to 12 significant digits, no float noise,
/// thousands grouped for reading, plain for copying.
public enum NumberText {
    public static func plain(_ value: Double, maxDecimals: Int = 10) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "∞" : "−∞") }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-7 {
            return trim(String(format: "%.8e", value), exponent: true)
        }
        let digits = Int(floor(log10(magnitude))) + 1
        let decimals = min(maxDecimals, max(0, 12 - digits))
        return trim(String(format: "%.\(decimals)f", value), exponent: false)
    }

    public static func grouped(_ value: Double, maxDecimals: Int = 10) -> String {
        let text = plain(value, maxDecimals: maxDecimals)
        guard !text.contains("e") else { return text }
        let negative = text.hasPrefix("-")
        let body = negative ? String(text.dropFirst()) : text
        let parts = body.split(separator: ".", maxSplits: 1)
        var integer = String(parts[0])
        var groups: [String] = []
        while integer.count > 3 {
            groups.insert(String(integer.suffix(3)), at: 0)
            integer.removeLast(3)
        }
        groups.insert(integer, at: 0)
        let joined = groups.joined(separator: ",") + (parts.count > 1 ? "." + parts[1] : "")
        return (negative ? "−" : "") + joined
    }

    /// Money: two decimals.
    public static func money(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var text = grouped(rounded, maxDecimals: 2)
        if let dot = text.firstIndex(of: ".") {
            if text.distance(from: dot, to: text.endIndex) == 2 { text += "0" }
        } else if !text.contains("e") {
            text += ".00"
        }
        return text
    }

    static func trim(_ text: String, exponent: Bool) -> String {
        if exponent {
            let parts = text.split(separator: "e", maxSplits: 1)
            guard parts.count == 2 else { return text }
            let mantissa = trim(String(parts[0]), exponent: false)
            let power = Int(parts[1]) ?? 0
            return "\(mantissa)e\(power)"
        }
        guard text.contains(".") else { return text == "-0" ? "0" : text }
        var out = text
        while out.hasSuffix("0") { out.removeLast() }
        if out.hasSuffix(".") { out.removeLast() }
        return out == "-0" ? "0" : out
    }
}
