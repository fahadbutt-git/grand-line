import Foundation

/// Every file Iceberg reads, in one place. The home folder is injected so the
/// tests can point everything at a temporary folder.
public struct IcebergPaths: Sendable, Equatable {
    public var home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// Iceberg's own settings and the user's widgets.
    public var configFolder: URL { home.appendingPathComponent(".config/grand-line/iceberg") }
    public var settingsFile: URL { configFolder.appendingPathComponent("iceberg.toml") }
    public var widgetsFolder: URL { configFolder.appendingPathComponent("widgets") }

    /// The shelf: a bookmark for each file on it (never the files themselves).
    public var shelfFile: URL { home.appendingPathComponent(".local/state/grand-line/iceberg/shelf.json") }

    /// The Pomodoro timer, so a running one carries on after a restart
    /// (`iceberg pomodoro status` reads it too).
    public var pomodoroFile: URL { home.appendingPathComponent(".local/state/grand-line/iceberg/pomodoro.json") }
}
