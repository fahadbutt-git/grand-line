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
        // Waybar's usual classes.
        "critical": .red, "urgent": .red, "success": .green, "info": .blue, "active": .accent,
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
    /// Waybar's `alt`: a second word for the state ("muted", "charging").
    public var alt: String?
    /// Shown when the pointer rests on the widget.
    public var tooltip: String?
    /// Waybar's `class`, one name or several.
    public var classes: [String]
    /// 0 to 100, drawn as a thin bar under the chip.
    public var percentage: Double?

    public init(text: String, icon: String? = nil, color: WidgetColor? = nil, failed: Bool = false,
                alt: String? = nil, tooltip: String? = nil, classes: [String] = [], percentage: Double? = nil) {
        self.text = text
        self.icon = icon
        self.color = color
        self.failed = failed
        self.alt = alt
        self.tooltip = tooltip
        self.classes = classes
        self.percentage = percentage
    }
}

/// Turns a command's output into what the widget shows.
///
/// The contract is Waybar's custom module, so its scripts work as they are:
///
/// - Output starting with `{` is read as one JSON object:
///   `{"text": "...", "alt": "...", "tooltip": "...", "class": "...", "percentage": 50}`,
///   plus Iceberg's own `icon` (an SF Symbol name) and `color` (a theme colour
///   name). Only `text` is needed; a number is shown as written. A `class`
///   that names a theme colour ("warning", "critical") colours the text when
///   `color` is not given.
/// - Anything else shows its first non-empty line (Waybar's plain-text form).
/// - Colour codes (ANSI escapes) are removed and the text is cut to `maxLength`.
///
/// A stream widget's every line goes through `parse` on its own.
public enum CommandOutputParser {
    public static let maxLength = 80
    public static let maxTooltipLength = 600

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
                shown.text = failureReason(result)
                shown.icon = shown.icon ?? "exclamationmark.triangle"
                shown.color = shown.color ?? .theme(.muted)
            }
            shown.failed = true
        }
        return shown
    }

    /// Why a run failed, in one line: the first line of its errors, or its exit status.
    public static func failureReason(_ result: CommandResult) -> String {
        if result.timedOut { return "No answer after \(formatSeconds(result.timeout))" }
        if let launchError = result.launchError { return launchError }
        let reason = firstLine(of: result.stderr).map(clean) ?? ""
        let code = result.exitCode.map { "exit \($0)" } ?? result.signal.map { "stopped by signal \($0)" } ?? "failed"
        return reason.isEmpty ? "Command failed (\(code))" : truncate(reason)
    }

    /// Reads stdout alone (first line, or JSON).
    public static func parse(_ stdout: String) -> WidgetDisplay {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            if let object = jsonObject(trimmed) { return display(fromJSON: object) }
            // Several JSON lines (a script that printed more than once): the last one wins.
            let lines = trimmed.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.count > 1 {
                for line in lines.reversed() where line.hasPrefix("{") {
                    if let object = jsonObject(line) { return display(fromJSON: object) }
                }
            }
        }
        return WidgetDisplay(text: truncate(clean(firstLine(of: stdout) ?? "")))
    }

    static func jsonObject(_ text: String) -> [String: JSONValue]? {
        guard let data = text.data(using: .utf8), let value = try? JSONValue.parse(data) else { return nil }
        return value.objectValue
    }

    static func display(fromJSON object: [String: JSONValue]) -> WidgetDisplay {
        func nonEmpty(_ v: JSONValue?) -> String? {
            guard let s = v?.displayText?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        let text = object["text"]?.displayText ?? object["label"]?.displayText ?? ""
        let icon = (object["icon"]?.stringValue).flatMap { s -> String? in
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        var classes: [String] = []
        switch object["class"] {
        case .string(let s)?:
            classes = s.split(separator: " ").map(String.init)
        case .array(let items)?:
            classes = items.compactMap { $0.stringValue }.filter { !$0.isEmpty }
        default:
            break
        }
        var color = object["color"]?.stringValue.flatMap(WidgetColor.parse)
        if color == nil {
            for c in classes {
                if let name = ThemeColorName(rawValue: c.lowercased()) ?? ThemeColorName.aliases[c.lowercased()] {
                    color = .theme(name)
                    break
                }
            }
        }
        var percentage: Double?
        if let p = object["percentage"]?.doubleValue ?? object["percentage"]?.stringValue.flatMap({ Double($0) }), p.isFinite {
            percentage = min(max(p, 0), 100)
        }
        let tooltip = nonEmpty(object["tooltip"]).map { t -> String in
            let c = t.split(separator: "\n", omittingEmptySubsequences: false).map { clean(String($0)) }.joined(separator: "\n")
            return c.count > maxTooltipLength ? String(c.prefix(maxTooltipLength - 1)) + "…" : c
        }
        return WidgetDisplay(text: truncate(clean(firstLine(of: text) ?? "")), icon: icon, color: color,
                             alt: nonEmpty(object["alt"]).map(clean), tooltip: tooltip,
                             classes: classes, percentage: percentage)
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
