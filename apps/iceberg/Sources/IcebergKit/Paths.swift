import Foundation

/// Every file Iceberg reads, in one place. The home folder is injected so the
/// tests can point everything at a temporary folder.
public struct IcebergPaths: Sendable, Equatable {
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
    /// Present while the theme follows macOS between dark and light (Nexus
    /// and Sight Settings, Appearance, "Follow macOS").
    public var themeFollowFile: URL { home.appendingPathComponent(".local/state/grand-line/theme-follows-macos") }
    /// Taken by the one app that runs `theme mode` after macOS switches.
    public var themeFollowLock: URL { home.appendingPathComponent(".local/state/grand-line/theme-follow.lock") }
    /// The package's `theme` command.
    public var themeCommand: URL { home.appendingPathComponent(".grand-line/bin/theme") }

    /// Iceberg's own settings and the user's widgets.
    public var configFolder: URL { home.appendingPathComponent(".config/grand-line/iceberg") }
    public var settingsFile: URL { configFolder.appendingPathComponent("iceberg.toml") }
    public var widgetsFolder: URL { configFolder.appendingPathComponent("widgets") }

    /// The shelf: a bookmark for each file on it (never the files themselves).
    public var shelfFile: URL { home.appendingPathComponent(".local/state/grand-line/iceberg/shelf.json") }
}
