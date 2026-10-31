import Foundation

/// Where Grand Line keeps what the providers read, from one home folder.
public struct GrandLinePaths: Sendable, Equatable {
    public let home: String

    public init(home: String = NSHomeDirectory()) {
        self.home = home
    }

    /// ~/.grand-line, the link to the package.
    public var package: String { home + "/.grand-line" }
    public var bin: String { package + "/bin" }
    public var commonShell: String { package + "/lib/bin-common.sh" }
    public var toggleState: String { package + "/lib/toggle-state.sh" }
    public var menu: String { package + "/config/grand-line/menu.tsv" }
    public var keybindings: String { package + "/config/grand-line/keybindings.tsv" }
    public var espansoMatches: String { package + "/config/espanso/match" }
    /// ~/.config/grand-line, your own additions.
    public var userConfig: String { home + "/.config/grand-line" }
    public var menuLocal: String { userConfig + "/menu.local.tsv" }
    public var bindingsLocal: String { userConfig + "/bindings.local.tsv" }
    public var savedSearches: String { userConfig + "/nexus/saved-searches.tsv" }
    /// Sight's settings: aliases, quicklinks and external providers.
    public var settings: String { userConfig + "/sight" }
    public var aliases: String { settings + "/aliases.tsv" }
    public var quicklinks: String { settings + "/quicklinks.tsv" }
    public var externalProviders: String { settings + "/providers.tsv" }
    /// Script commands: executables that print rows as JSON lines (ScriptCommands).
    public var scripts: String { settings + "/scripts" }
    /// ~/.local/state/grand-line, where Nexus writes its selection.
    public var localState: String { home + "/.local/state/grand-line" }
    /// Nexus's selection while it is in front, one path per line (lib/bin-common.sh finder_selection).
    public var nexusSelection: String { localState + "/nexus-selection" }
    public var downloads: String { home + "/Downloads" }
    /// Maccy's history (SwiftData, in its sandbox container). Read only, from a copy.
    public var maccyStore: String { home + "/Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite" }
    /// Sight's state: learned ranking, the name index and exchange rates.
    public var state: String { home + "/Library/Application Support/Sight" }
    public var usage: String { state + "/usage.json" }
    public var rates: String { state + "/exchange-rates.json" }
    public var index: String { state + "/names.index" }
    /// Zen keeps Firefox's layout: Profiles/<name>/places.sqlite.
    public var zen: String { home + "/Library/Application Support/zen/Profiles" }

    public func command(_ name: String) -> String { bin + "/" + name }

    /// Replaces a leading ~ with the home folder.
    public func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        return path
    }

    /// Replaces the home folder with ~, for display.
    public func abbreviate(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
