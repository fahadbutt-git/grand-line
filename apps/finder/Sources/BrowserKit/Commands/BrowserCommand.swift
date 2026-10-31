import Foundation

/// Every action Nexus has. Each one has a menu item with its shortcut
/// (menus are how Mac users find shortcuts), listed in `CommandCatalog`.
public enum BrowserCommand: String, CaseIterable, Codable, Sendable {
    // File
    case newWindow, newTab, newFolder, newFolderWithSelection
    case open, openWithOther, closeWindow, closeAllWindows
    case getInfo, rename, compress, duplicate, makeAlias, showOriginal, quickLook, fullScreenPreview
    case moveToTrash, putBack, emptyTrash, emptyTrashNow
    case eject, extract, extractTo
    case share, airDrop, copyPath, addToSidebar, showAllInSidebar
    case tagRed, tagOrange, tagYellow, tagGreen, tagBlue, tagPurple, tagGray, removeTags, editTags
    case find, saveSearch, cleanClutter
    // Edit
    case undo, redo, cut, copy, paste, moveHere, selectAll, deselectAll
    // View
    case viewIcons, viewList, viewColumns, viewGallery, viewPanes
    case sortName, sortKind, sortLastOpened, sortAdded, sortModified, sortCreated, sortSize, sortTags, sortManual
    case keepFoldersOnTop, groupNone, groupKind
    case showViewOptions, rememberView, useAsDefaultView
    case toggleHidden, togglePreview, toggleInspector, toggleSidebar, toggleStatusBar, toggleToolbar, togglePathBar
    case biggerIcons, smallerIcons, showTransfers
    // Go
    case back, forward, enclosingFolder, enclosingFolderInNewWindow, openSelection
    case goRecents, goDocuments, goDesktop, goDownloads, goHome, goComputer, goAirDrop, goNetwork, goICloud
    case goApplications, goUtilities, goLibrary, goDrive, goTrash
    case goToFolder, connectToServer
    // Panes
    case nextPane, previousPane, copyToNextPane, moveToNextPane
    case onePane, twoPanes, threePanes, fourPanes
    case pinWindow, saveWorkspace
    // Tools
    case openTerminal, openClaude
    case transcodeVideo, transcodePNG, transcodeJPEG, transcodePDF, transcodeText
}

public enum MenuGroup: String, CaseIterable, Sendable {
    case file = "File"
    case edit = "Edit"
    case view = "View"
    case go = "Go"
    case panes = "Panes"
    case tools = "Tools"
}

/// Where a command applies, so one key can mean two things: Cmd+Delete moves
/// to the Trash but puts back inside it; Cmd+E ejects but extracts in an archive.
public enum CommandContext: Sendable, Equatable {
    case any
    case archive
    case notArchive
    case trash
    case notTrash

    public func matches(inArchive: Bool, inTrash: Bool) -> Bool {
        switch self {
        case .any: return true
        case .archive: return inArchive
        case .notArchive: return !inArchive
        case .trash: return inTrash
        case .notTrash: return !inTrash
        }
    }
}

public struct CommandSpec: Sendable {
    public let command: BrowserCommand
    public let title: String
    /// The first is shown in the menu; the others also work (Return opens like Cmd+O).
    public let shortcuts: [Shortcut]
    public let menu: MenuGroup
    public let context: CommandContext
    /// A separator goes above this item.
    public let startsGroup: Bool
    /// A submenu title the item sits in ("Sort By", "Tags", "Transcode").
    public let submenu: String?
}
