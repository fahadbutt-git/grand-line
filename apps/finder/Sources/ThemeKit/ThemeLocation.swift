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

    /// A theme by name: its file, else a built-in theme of that name, else nil.
    public func load(named name: String) -> Theme? {
        if let values = ThemeFile.read(file(named: name)) { return Theme(name: name, values: values) }
        return BuiltInThemes.named(name)
    }

    /// The active theme, falling back to Graphite.
    public func load() -> Theme {
        if let name = activeName(), let theme = load(named: name) { return theme }
        return BuiltInThemes.named(Self.fallbackName)!
    }
}
