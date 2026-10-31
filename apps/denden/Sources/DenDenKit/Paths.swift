import Foundation

/// Every file Den Den reads, in one place. The home folder is injected so the
/// tests can point everything at a temporary folder.
public struct DenDenPaths: Sendable, Equatable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// The theme's name, one line (written by `theme set` and `theme pick`).
    public var themeState: URL { home.appendingPathComponent(".local/state/grand-line/theme") }
    /// The rendered theme files; `theme set` replaces this folder all at
    /// once, so a change here means the theme changed.
    public var renderedTheme: URL { home.appendingPathComponent(".local/state/grand-line/current/theme") }
    /// The package's theme files (`~/.grand-line` links to the package).
    public var themesFolder: URL { home.appendingPathComponent(".grand-line/config/themes") }
    public func themeFile(named name: String) -> URL {
        themesFolder.appendingPathComponent("\(name).theme")
    }

    /// Den Den's own settings and the user's widgets.
    public var configFolder: URL { home.appendingPathComponent(".config/grand-line/denden") }
    public var settingsFile: URL { configFolder.appendingPathComponent("denden.toml") }
    public var widgetsFolder: URL { configFolder.appendingPathComponent("widgets") }
}
