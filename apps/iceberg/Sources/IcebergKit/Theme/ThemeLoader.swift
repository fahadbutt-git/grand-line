import Foundation

/// Reads the active theme the way the rest of the package does: the name from
/// `~/.local/state/grand-line/theme`, the colours from
/// `~/.grand-line/config/themes/<name>.theme` with its EXTENDS parents, through
/// the format 1 checker (ThemeSpec.swift, as `theme check`). Always returns a
/// theme; what was missing or wrong comes back as issues with their lines.
public enum ThemeLoader {
    public static let defaultName = "graphite"

    /// Posted (distributed) by `theme set` and `theme apply` once the new
    /// theme is rendered: reload at once rather than wait for the file watch.
    public static let changedNotification = Notification.Name(ThemeSpec.changedNotification)

    /// The theme's name from the state file, or "graphite".
    public static func currentName(paths: IcebergPaths) -> String {
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

    /// Themes Iceberg carries itself, so they need no file.
    public static let builtIn: [String: Theme] = ["graphite": .graphite, "daylight": .daylight]

    /// A missing file is only an issue for a theme Iceberg does not carry: with no
    /// theme chosen yet (a build run before setup), or a built-in one, it uses
    /// its own copy and says nothing.
    public static func load(paths: IcebergPaths) -> (Theme, [ConfigIssue]) {
        load(paths: paths, named: currentName(paths: paths))
    }

    /// Whether the theme follows the macOS appearance.
    public static func followsSystem(paths: IcebergPaths) -> Bool {
        FileManager.default.fileExists(atPath: paths.themeFollowFile.path)
    }

    /// The theme to show: the state file's, or, while following macOS, its
    /// variant for the system's appearance, by `theme mode`'s rules (FAMILY-dark
    /// and FAMILY-light; Graphite and Daylight pair up).
    public static func followedName(paths: IcebergPaths, systemIsDark: Bool) -> String {
        let name = currentName(paths: paths)
        guard followsSystem(paths: paths) else { return name }
        return variant(of: name, systemIsDark: systemIsDark, paths: paths) ?? name
    }

    /// The same, asking for macOS's appearance at the moment of the call (and
    /// only while following it). The app reloads with this, never with an
    /// appearance it noted earlier: a reload after `theme mode dark` from
    /// Nexus or Sight can arrive before the appearance notice does.
    public static func followedName(paths: IcebergPaths, currentAppearanceIsDark: () -> Bool) -> String {
        guard followsSystem(paths: paths) else { return currentName(paths: paths) }
        return followedName(paths: paths, systemIsDark: currentAppearanceIsDark())
    }

    /// The other variant to switch to, or nil when `name` already matches or has none.
    public static func variant(of name: String, systemIsDark: Bool, paths: IcebergPaths) -> String? {
        let target: String
        if name == "graphite" || name == "daylight" {
            target = systemIsDark ? "graphite" : "daylight"
        } else {
            // A light variant may take FAMILY from the dark one it EXTENDS.
            guard let family = resolvedFields(paths: paths, named: name)["FAMILY"].flatMap(sanitizedName) else { return nil }
            target = family + (systemIsDark ? "-dark" : "-light")
        }
        guard target != name,
              FileManager.default.fileExists(atPath: paths.themeFile(named: target).path) || builtIn[target] != nil
        else { return nil }
        return target
    }

    public static func load(paths: IcebergPaths, named name: String) -> (Theme, [ConfigIssue]) {
        let url = paths.themeFile(named: name)
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else {
            if let own = builtIn[name] { return (own, []) }
            let fallback = Theme.graphite
            return (fallback, [ConfigIssue(file: "\(name).theme", message: "theme file not found; using \(fallback.label)", severity: .warning)])
        }
        return parse(text, name: name, folder: paths.themesFolder)
    }

    /// Every key of a theme file as the checker leaves it: EXTENDS followed,
    /// values cleaned, defaults filled. Empty when there is no file (a
    /// built-in theme). For the keys `Theme` does not hold (NOTCH_*, ICON_*).
    public static func resolvedFields(paths: IcebergPaths, named name: String) -> [String: String] {
        guard let source = ThemeSource.resolve(url: paths.themeFile(named: name)) else { return [:] }
        return check(source).values
    }

    /// The checker, with the built-in theme of the file's mode standing in for
    /// required keys that are missing or wrong.
    static func check(_ source: ThemeSource) -> ThemeValidation {
        let mode = source.entries["MODE"].flatMap { Theme.Mode(rawValue: $0.value.lowercased()) }
        return ThemeSpec.validate(source, fallback: (mode == .light ? Theme.daylight : Theme.graphite).fields)
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

    /// A theme file's text. With `folder`, EXTENDS reads the parent from it.
    public static func parse(_ text: String, name: String, folder: URL? = nil) -> (Theme, [ConfigIssue]) {
        let source = ThemeSource.resolve(text: text, file: "\(name).theme", folder: folder)
        let checked = check(source)
        let f = checked.values
        let mode = f["MODE"].flatMap(Theme.Mode.init(rawValue:))
        let base = mode == .light ? Theme.daylight : Theme.graphite
        var theme = base
        theme.name = name
        theme.mode = mode ?? .dark
        theme.label = f["LABEL"].flatMap { $0.isEmpty ? nil : $0 } ?? name.capitalized

        func color(_ key: String, _ keyPath: WritableKeyPath<Theme, RGB>) {
            if let rgb = f[key].flatMap(RGB.init(hex:)) { theme[keyPath: keyPath] = rgb }
        }
        color("TERM_BG", \.background)
        color("TERM_FG", \.foreground)
        color("TERM_SELECTION", \.selection)
        color("HIGHLIGHT", \.highlight)
        color("MUTED", \.muted)
        color("ACCENT_HEX", \.accent)
        color("BG_LIGHTER", \.backgroundLighter)
        color("BG_DARKER", \.backgroundDarker)
        let colours = (f["PALETTE"] ?? "").split(separator: " ").compactMap { RGB(hex: String($0)) }
        if colours.count == 16 { theme.palette = colours }
        return (theme, checked.diagnostics.map(ConfigIssue.init(theme:)))
    }
}

extension ConfigIssue {
    /// A checker diagnostic, keeping its file (a parent's, when the key came from one) and line.
    init(theme diagnostic: ThemeDiagnostic) {
        self.init(file: diagnostic.file, line: diagnostic.line, message: diagnostic.message,
                  severity: diagnostic.severity == .error ? .error : .warning)
    }
}
