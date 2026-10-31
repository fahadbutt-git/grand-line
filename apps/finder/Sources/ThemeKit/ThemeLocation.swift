import Foundation

/// Where Grand Line keeps the active theme: its name in
/// ~/.local/state/grand-line/theme and its file in ~/.grand-line/config/themes.
public struct ThemeLocation: Sendable, Equatable {
    public let stateFile: URL
    public let themesFolder: URL

    public static let fallbackName = "graphite"

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        stateFile = home.appendingPathComponent(".local/state/grand-line/theme")
        themesFolder = home.appendingPathComponent(".grand-line/config/themes", isDirectory: true)
    }

    public init(stateFile: URL, themesFolder: URL) {
        self.stateFile = stateFile
        self.themesFolder = themesFolder
    }

    /// The name written by `theme set`, or nil before a theme was ever chosen.
    public func activeName() -> String? {
        guard let text = try? String(contentsOf: stateFile, encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.contains("/") ? nil : name
    }

    public func file(named name: String) -> URL {
        themesFolder.appendingPathComponent(name + ".theme")
    }

    /// A theme by name: its file (with its EXTENDS parents, checked, defaults
    /// filled), else a built-in theme of that name, else nil.
    public func load(named name: String) -> Theme? {
        if let source = ThemeSource.resolve(url: file(named: name)) { return Theme(name: name, source: source) }
        return BuiltInThemes.named(name)
    }

    /// What `theme check NAME` reports for a theme file, or nil when there is no file.
    public func check(named name: String) -> ThemeValidation? {
        ThemeSource.resolve(url: file(named: name)).map { ThemeSpec.validate($0) }
    }

    /// The active theme, falling back to Graphite.
    public func load() -> Theme {
        if let name = activeName(), let theme = load(named: name) { return theme }
        return BuiltInThemes.named(Self.fallbackName)!
    }

    // MARK: Following the macOS appearance

    /// Present while the theme follows macOS between its dark and light
    /// variants (Settings, Appearance, "Follow macOS"). Every app reads it.
    public var followFile: URL {
        stateFile.deletingLastPathComponent().appendingPathComponent("theme-follows-macos")
    }

    /// Taken by the one app that runs `theme mode` after macOS switches.
    public var followLock: URL {
        stateFile.deletingLastPathComponent().appendingPathComponent("theme-follow.lock")
    }

    /// ~/.grand-line, the package the themes folder belongs to.
    public var packageFolder: URL {
        themesFolder.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// The `theme` command that writes the state file and renders the templates.
    public var themeCommand: URL {
        packageFolder.appendingPathComponent("bin/theme")
    }

    public func followsSystem() -> Bool {
        FileManager.default.fileExists(atPath: followFile.path)
    }

    public func setFollowsSystem(_ on: Bool) throws {
        if on {
            try FileManager.default.createDirectory(at: followFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("yes\n".utf8).write(to: followFile, options: .atomic)
        } else if FileManager.default.fileExists(atPath: followFile.path) {
            try FileManager.default.removeItem(at: followFile)
        }
    }

    /// The FAMILY= of a theme file, or nil for a theme without a pair.
    public func family(of name: String) -> String? {
        if ThemeFollow.systemPair.contains(name) { return ThemeFollow.systemFamily }
        // A light variant may take FAMILY from the dark one it EXTENDS.
        let family = ThemeSource.resolve(url: file(named: name))?.entries["FAMILY"]?.value.trimmingCharacters(in: .whitespaces) ?? ""
        return family.isEmpty ? nil : family
    }

    /// The name to show: the active one, or, while following macOS, its
    /// variant for `systemIsDark` when the theme has one.
    public func resolvedName(systemIsDark: Bool?) -> String {
        let name = activeName() ?? Self.fallbackName
        guard let systemIsDark, followsSystem() else { return name }
        return ThemeFollow.variant(of: name, systemIsDark: systemIsDark, family: family(of: name)) {
            FileManager.default.fileExists(atPath: file(named: $0).path) || BuiltInThemes.named($0) != nil
        } ?? name
    }

    /// The active theme as `resolvedName` names it.
    public func load(systemIsDark: Bool?) -> Theme {
        guard systemIsDark != nil, activeName() != nil, followsSystem() else { return load() }
        return load(named: resolvedName(systemIsDark: systemIsDark)) ?? load()
    }
}
