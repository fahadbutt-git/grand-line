import Foundation

/// A colour a widget asks for. Widgets name theme colours so they follow the
/// theme; a hex colour is accepted but DESIGN.md prefers names.
public enum WidgetColor: Equatable, Sendable {
    case theme(ThemeColorName)
    case hex(RGB)

    public static func parse(_ raw: String) -> WidgetColor? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let name = ThemeColorName(rawValue: s) { return .theme(name) }
        if let alias = ThemeColorName.aliases[s] { return .theme(alias) }
        if let rgb = RGB(hex: s) { return .hex(rgb) }
        return nil
    }
}

/// The theme colours a widget may name.
public enum ThemeColorName: String, Sendable, CaseIterable {
    case foreground, muted, highlight, accent, red, green, yellow, blue, magenta, cyan

    static let aliases: [String: ThemeColorName] = [
        "fg": .foreground, "text": .foreground, "normal": .foreground, "default": .foreground,
        "dim": .muted, "grey": .muted, "gray": .muted, "secondary": .muted,
        "focus": .highlight, "ok": .green, "good": .green, "warn": .yellow, "warning": .yellow,
        "error": .red, "bad": .red, "purple": .magenta,
    ]
}

/// What a widget shows after its command ran.
public struct WidgetDisplay: Equatable, Sendable {
    public var text: String
    /// Replaces the widget's configured symbol for this run.
    public var icon: String?
    public var color: WidgetColor?
    /// Set when the command failed; the text then says why.
    public var failed: Bool

    public init(text: String, icon: String? = nil, color: WidgetColor? = nil, failed: Bool = false) {
        self.text = text
        self.icon = icon
        self.color = color
        self.failed = failed
    }
}

/// Turns a command's output into what the widget shows.
///
/// - Output starting with `{` is read as JSON: `{"text": "...", "icon": "...", "color": "..."}`.
///   Only `text` is needed; a number is shown as written.
/// - Anything else shows its first non-empty line.
/// - Colour codes (ANSI escapes) are removed and the text is cut to `maxLength`.
public enum CommandOutputParser {
    public static let maxLength = 80

    public static func display(for result: CommandResult) -> WidgetDisplay {
        if result.timedOut {
            return WidgetDisplay(text: "No answer after \(formatSeconds(result.timeout))", icon: "clock.badge.exclamationmark", color: .theme(.muted), failed: true)
        }
        if let launchError = result.launchError {
            return WidgetDisplay(text: launchError, icon: "exclamationmark.triangle", color: .theme(.muted), failed: true)
        }
        var shown = parse(result.stdout)
        let succeeded = result.exitCode == 0
        if !succeeded {
            if shown.text.isEmpty {
                let reason = firstLine(of: result.stderr).map(clean) ?? ""
                let code = result.exitCode.map { "exit \($0)" } ?? result.signal.map { "stopped by signal \($0)" } ?? "failed"
                shown.text = reason.isEmpty ? "Command failed (\(code))" : truncate(reason)
                shown.icon = shown.icon ?? "exclamationmark.triangle"
                shown.color = shown.color ?? .theme(.muted)
            }
            shown.failed = true
        }
        return shown
    }

    /// Reads stdout alone (first line, or JSON).
    public static func parse(_ stdout: String) -> WidgetDisplay {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let value = try? JSONValue.parse(data), let object = value.objectValue {
            let text = object["text"]?.displayText ?? object["label"]?.displayText ?? ""
            let icon = (object["icon"]?.stringValue).flatMap { s -> String? in
                let t = s.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
            let color = object["color"]?.stringValue.flatMap(WidgetColor.parse)
            return WidgetDisplay(text: truncate(clean(firstLine(of: text) ?? "")), icon: icon, color: color)
        }
        return WidgetDisplay(text: truncate(clean(firstLine(of: stdout) ?? "")))
    }

    static func firstLine(of text: String) -> String? {
        for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Removes ANSI escape sequences and other control characters.
    public static func clean(_ text: String) -> String {
        var out = ""
        var scalars = text.unicodeScalars.makeIterator()
        while let s = scalars.next() {
            if s == "\u{1B}" {
                // CSI: ESC [ ... final byte in @...~ ; other escapes: skip one.
                guard let next = scalars.next() else { break }
                if next == "[" {
                    while let c = scalars.next() {
                        if (0x40...0x7E).contains(c.value) { break }
                    }
                } else if next == "]" {
                    // OSC: up to BEL or ESC \
                    while let c = scalars.next() {
                        if c == "\u{07}" || c == "\u{1B}" { break }
                    }
                }
                continue
            }
            if s == "\t" { out.unicodeScalars.append(" "); continue }
            if s.properties.generalCategory == .control { continue }
            out.unicodeScalars.append(s)
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    static func formatSeconds(_ s: TimeInterval) -> String {
        s.rounded() == s ? "\(Int(s)) s" : String(format: "%.1f s", s)
    }
}
