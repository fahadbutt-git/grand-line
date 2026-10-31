import Foundation

/// Reads the active theme the way the rest of the package does: the name from
/// `~/.local/state/grand-line/theme`, the colours from
/// `~/.grand-line/config/themes/<name>.theme`. Always returns a theme; what was
/// missing or wrong comes back as issues.
public enum ThemeLoader {
    public static let defaultName = "graphite"

    /// The theme's name from the state file, or "graphite".
    public static func currentName(paths: DenDenPaths) -> String {
        guard let data = FileManager.default.contents(atPath: paths.themeState.path),
              let text = String(data: data, encoding: .utf8) else { return defaultName }
        return sanitizedName(text) ?? defaultName
    }

    /// The first line, if it is a safe file name (letters, digits, - and _).
    public static func sanitizedName(_ text: String) -> String? {
        let first = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? ""
        let name = first.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return name
    }

    public static func load(paths: DenDenPaths) -> (Theme, [ConfigIssue]) {
        let name = currentName(paths: paths)
        let url = paths.themeFile(named: name)
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else {
            let fallback = name == "daylight" ? Theme.daylight : Theme.graphite
            return (fallback, [ConfigIssue(file: "\(name).theme", message: "theme file not found; using \(fallback.label)", severity: .warning)])
        }
        return parse(text, name: name)
    }

    /// KEY=VALUE lines, values optionally in quotes, # comments.
    public static func fields(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            var key = line[..<eq].trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("export ") { key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let q = value.first, q == "\"" || q == "'" {
                let body = value.dropFirst()
                if let end = body.firstIndex(of: q) { value = String(body[..<end]) } else { value = String(body) }
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            out[key] = value
        }
        return out
    }

    public static func parse(_ text: String, name: String) -> (Theme, [ConfigIssue]) {
        let f = fields(text)
        let file = "\(name).theme"
        var issues: [ConfigIssue] = []

        let modeText = f["MODE"]?.lowercased()
        let mode = Theme.Mode(rawValue: modeText ?? "")
        if mode == nil { issues.append(ConfigIssue(file: file, message: "MODE must be dark or light; using dark", severity: .warning)) }
        let base = mode == .light ? Theme.daylight : Theme.graphite
        var theme = base
        theme.name = name
        theme.mode = mode ?? .dark
        theme.label = f["LABEL"].flatMap { $0.isEmpty ? nil : $0 } ?? name.capitalized

        func color(_ key: String, _ keyPath: WritableKeyPath<Theme, RGB>) {
            guard let raw = f[key] else {
                issues.append(ConfigIssue(file: file, message: "\(key) is missing; using \(base.label)'s", severity: .warning))
                return
            }
            guard let rgb = RGB(hex: raw) else {
                issues.append(ConfigIssue(file: file, message: "\(key)=\(raw) is not a hex colour", severity: .warning))
                return
            }
            theme[keyPath: keyPath] = rgb
        }
        color("TERM_BG", \.background)
        color("TERM_FG", \.foreground)
        color("TERM_SELECTION", \.selection)
        color("HIGHLIGHT", \.highlight)
        color("MUTED", \.muted)
        color("ACCENT_HEX", \.accent)
        color("BG_LIGHTER", \.backgroundLighter)
        color("BG_DARKER", \.backgroundDarker)

        if let raw = f["PALETTE"] {
            let colours = raw.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { RGB(hex: String($0)) }
            if colours.count >= 8 { theme.palette = colours }
            else { issues.append(ConfigIssue(file: file, message: "PALETTE needs 16 hex colours", severity: .warning)) }
        } else {
            issues.append(ConfigIssue(file: file, message: "PALETTE is missing; using \(base.label)'s", severity: .warning))
        }
        return (theme, issues)
    }
}
