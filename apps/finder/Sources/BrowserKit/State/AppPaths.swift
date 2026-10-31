import Foundation

/// Where Log Pose keeps things: state in Application Support, settings in
/// ~/.config/grand-line/logpose, and the package's shared files.
public struct AppPaths: Sendable, Equatable {
    public let home: URL
    public let support: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, support: URL? = nil) {
        self.home = home
        self.support = support ?? home.appendingPathComponent("Library/Application Support/Log Pose", isDirectory: true)
    }

    public var viewPreferences: URL { support.appendingPathComponent("view-settings.json") }
    public var workspaces: URL { support.appendingPathComponent("Workspaces", isDirectory: true) }
    public var trashLedger: URL { support.appendingPathComponent("trash-ledger.json") }
    public var nameIndex: URL { support.appendingPathComponent("name-index.snapshot") }
    public var recents: URL { support.appendingPathComponent("recents.json") }
    public var sidebarHidden: URL { support.appendingPathComponent("sidebar-hidden.json") }

    public var settingsFolder: URL { home.appendingPathComponent(".config/grand-line/logpose", isDirectory: true) }
    public var settings: URL { settingsFolder.appendingPathComponent("settings.json") }
    public var savedSearches: URL { settingsFolder.appendingPathComponent("saved-searches.tsv") }

    public var defaultApps: URL { home.appendingPathComponent(".grand-line/config/grand-line/default-apps.tsv") }
    public var transcode: URL { home.appendingPathComponent(".grand-line/bin/transcode") }
    /// Rewritten on every selection change while Log Pose is frontmost.
    public var selectionFile: URL { home.appendingPathComponent(".local/state/grand-line/logpose-selection") }
    public var trash: URL { home.appendingPathComponent(".Trash", isDirectory: true) }
}
