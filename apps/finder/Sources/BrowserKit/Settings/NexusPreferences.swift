import FileKit
import Foundation

/// Where Cmd+N, a launch and a click on the Dock icon open a window.
public enum NewWindowTarget: String, CaseIterable, Sendable {
    /// The folder of the window in front, else home (as before Settings).
    case currentFolder
    case home
    case desktop
    case documents
    case downloads
    case drive
    case recents

    public var title: String {
        switch self {
        case .currentFolder: return "The current folder"
        case .home: return "Home"
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        case .downloads: return "Downloads"
        case .drive: return "Google Drive (My Drive)"
        case .recents: return "Recents"
        }
    }

    /// - Parameter current: the front window's folder, if any.
    public func location(current: URL?, home: URL, drives: [GoogleDrive]) -> BrowserLocation {
        switch self {
        case .currentFolder: return .folder(current ?? home)
        case .home: return .folder(home)
        case .desktop: return .folder(home.appendingPathComponent("Desktop", isDirectory: true))
        case .documents: return .folder(home.appendingPathComponent("Documents", isDirectory: true))
        case .downloads: return .folder(home.appendingPathComponent("Downloads", isDirectory: true))
        case .drive: return .folder(drives.first?.myDrive ?? home)
        case .recents: return .recents
        }
    }
}

/// What Return does on a selected item. Finder renames; Nexus opens (R4).
public enum ReturnKeyAction: String, CaseIterable, Sendable {
    case open
    case rename

    public var title: String {
        switch self {
        case .open: return "Opens the item (F2 renames)"
        case .rename: return "Renames the item, as in Finder (Cmd+O opens)"
        }
    }

    /// The command a key runs, after this choice: plain Return renames instead of opening.
    public func command(_ command: BrowserCommand, for shortcut: Shortcut) -> BrowserCommand {
        guard self == .rename, command == .open, shortcut == Shortcut(.returnKey) else { return command }
        return .rename
    }
}

/// Where a search typed in a folder starts; the chips widen it from there (R3).
public enum DefaultSearchScope: String, CaseIterable, Sendable {
    case currentFolder
    case home
    case drive
    case mac

    public var title: String {
        switch self {
        case .currentFolder: return "The current folder"
        case .home: return "Home"
        case .drive: return "Google Drive"
        case .mac: return "This Mac"
        }
    }

    /// Outside a folder (Recents, an archive) the current folder means home.
    public func scope(folder: URL?) -> SearchScope {
        switch self {
        case .currentFolder: return folder.map { .folder($0.path) } ?? .home
        case .home: return .home
        case .drive: return .drive
        case .mac: return .mac
        }
    }
}

/// Every choice in Nexus's Settings window, kept in its defaults domain
/// (com.grandline.nexus). View defaults stay in view-settings.json and
/// hidden sidebar items in sidebar-hidden.json, as before.
public struct NexusPreferences: Equatable, Sendable {
    public enum Key {
        public static let newWindowTarget = "NewWindowTarget"
        public static let openFoldersInTabs = "OpenFoldersInTabs"
        public static let returnKey = "ReturnKeyAction"
        public static let showPathBar = "ShowPathBar"
        public static let showStatusBar = "ShowStatusBar"
        public static let showKindColours = "ShowKindColours"
        public static let includeContentMatches = "IncludeContentMatches"
        public static let defaultSearchScope = "DefaultSearchScope"
        public static let showHiddenFiles = "ShowHiddenFiles"
        public static let showAllExtensions = "ShowAllExtensions"
        public static let warnBeforeEmptyingTrash = "WarnBeforeEmptyingTrash"
        public static let warnBeforeChangingExtension = "WarnBeforeChangingExtension"
    }

    public var newWindowTarget = NewWindowTarget.currentFolder
    /// New windows join the front window as tabs (the window's tabbing mode).
    public var openFoldersInTabs = true
    public var returnKey = ReturnKeyAction.open
    public var showPathBar = true
    public var showStatusBar = true
    /// File icons in the list take their kind's colour (KIND_* in the theme).
    public var showKindColours = true
    /// Spotlight's content matches join the name index's matches.
    public var includeContentMatches = true
    public var defaultSearchScope = DefaultSearchScope.currentFolder
    /// New windows start with hidden files shown.
    public var showHiddenFiles = false
    public var showAllExtensions = true
    public var warnBeforeEmptyingTrash = true
    public var warnBeforeChangingExtension = true
    public var sidebar = SidebarLayout()

    public init() {}

    public init(defaults: UserDefaults) {
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        newWindowTarget = defaults.string(forKey: Key.newWindowTarget).flatMap(NewWindowTarget.init(rawValue:)) ?? .currentFolder
        openFoldersInTabs = flag(Key.openFoldersInTabs, true)
        returnKey = defaults.string(forKey: Key.returnKey).flatMap(ReturnKeyAction.init(rawValue:)) ?? .open
        showPathBar = flag(Key.showPathBar, true)
        showStatusBar = flag(Key.showStatusBar, true)
        showKindColours = flag(Key.showKindColours, true)
        includeContentMatches = flag(Key.includeContentMatches, true)
        defaultSearchScope = defaults.string(forKey: Key.defaultSearchScope).flatMap(DefaultSearchScope.init(rawValue:)) ?? .currentFolder
        showHiddenFiles = flag(Key.showHiddenFiles, false)
        showAllExtensions = flag(Key.showAllExtensions, true)
        warnBeforeEmptyingTrash = flag(Key.warnBeforeEmptyingTrash, true)
        warnBeforeChangingExtension = flag(Key.warnBeforeChangingExtension, true)
        sidebar = SidebarLayout(defaults: defaults)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(newWindowTarget.rawValue, forKey: Key.newWindowTarget)
        defaults.set(openFoldersInTabs, forKey: Key.openFoldersInTabs)
        defaults.set(returnKey.rawValue, forKey: Key.returnKey)
        defaults.set(showPathBar, forKey: Key.showPathBar)
        defaults.set(showStatusBar, forKey: Key.showStatusBar)
        defaults.set(showKindColours, forKey: Key.showKindColours)
        defaults.set(includeContentMatches, forKey: Key.includeContentMatches)
        defaults.set(defaultSearchScope.rawValue, forKey: Key.defaultSearchScope)
        defaults.set(showHiddenFiles, forKey: Key.showHiddenFiles)
        defaults.set(showAllExtensions, forKey: Key.showAllExtensions)
        defaults.set(warnBeforeEmptyingTrash, forKey: Key.warnBeforeEmptyingTrash)
        defaults.set(warnBeforeChangingExtension, forKey: Key.warnBeforeChangingExtension)
        sidebar.save(to: defaults)
    }
}

public extension FileItem {
    /// The name as a row shows it: without its extension when Settings, Advanced
    /// turns "Show all filename extensions" off. Folders, packages and items in
    /// archives always show their full name.
    func shownName(allExtensions: Bool) -> String {
        guard !allExtensions, !isFolder, !isPackage, !isInArchive, !ext.isEmpty else { return name }
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? name : base
    }

    /// A name typed over the shown one: the hidden extension comes back unless a new one was typed.
    func typedName(_ typed: String, allExtensions: Bool) -> String {
        guard shownName(allExtensions: allExtensions) != name, (typed as NSString).pathExtension.isEmpty else { return typed }
        return typed + "." + (name as NSString).pathExtension
    }
}
