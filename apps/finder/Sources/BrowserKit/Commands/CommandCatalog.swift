import Foundation

/// Titles, shortcuts and menus for every command, in menu order. Every Finder
/// shortcut keeps its Finder meaning; Nexus only adds keys Finder leaves
/// free. Return opens as well as Cmd+O and F2 renames (R4), Cmd+Shift+G opens
/// the editable path bar with fuzzy folder search (Finder's Go to Folder, R5),
/// and Nexus's own tools sit on Control+Option (Ghostty, Claude Code and
/// transcoding, R31, R33), which Finder does not use.
public enum CommandCatalog {
    public static let all: [CommandSpec] = file + edit + view + go + panes + tools

    public static func spec(_ command: BrowserCommand) -> CommandSpec {
        byCommand[command] ?? CommandSpec(command: command, title: command.rawValue, shortcuts: [], menu: .file, context: .any, startsGroup: false, submenu: nil)
    }

    static let byCommand: [BrowserCommand: CommandSpec] = {
        var table: [BrowserCommand: CommandSpec] = [:]
        for spec in all where table[spec.command] == nil { table[spec.command] = spec }
        return table
    }()

    private static func item(
        _ command: BrowserCommand, _ title: String, _ shortcuts: [Shortcut] = [], _ menu: MenuGroup,
        context: CommandContext = .any, group: Bool = false, submenu: String? = nil
    ) -> CommandSpec {
        CommandSpec(command: command, title: title, shortcuts: shortcuts, menu: menu, context: context, startsGroup: group, submenu: submenu)
    }

    private static func cmd(_ key: String, _ extra: Shortcut.Modifiers = []) -> Shortcut { .command(key, extra) }

    /// Control+Option, the layer Finder leaves free, for Nexus's own tools.
    /// (Control+Shift+Command+3 and 4 are taken by macOS for screenshots.)
    private static func tool(_ key: String) -> Shortcut { Shortcut(.character(key), [.control, .option]) }

    static let file: [CommandSpec] = [
        item(.newWindow, "New Window", [cmd("n")], .file),
        item(.newTab, "New Tab", [cmd("t")], .file),
        item(.newFolder, "New Folder", [cmd("n", .shift)], .file),
        item(.newFolderWithSelection, "New Folder with Selection", [cmd("n", .control)], .file),
        item(.open, "Open", [cmd("o"), Shortcut(.returnKey)], .file, group: true),
        item(.openWithOther, "Open With Other App…", [cmd("o", .control)], .file),
        item(.closeWindow, "Close Window", [cmd("w")], .file),
        item(.closeAllWindows, "Close All Windows", [cmd("w", .option)], .file),
        item(.getInfo, "Get Info", [cmd("i")], .file, group: true),
        item(.rename, "Rename", [Shortcut(.function(2))], .file),
        item(.compress, "Compress", [cmd("z", .control)], .file),
        item(.duplicate, "Duplicate", [cmd("d")], .file),
        item(.makeAlias, "Make Alias", [cmd("a", .control), cmd("l")], .file),
        item(.showOriginal, "Show Original", [cmd("r")], .file),
        item(.quickLook, "Quick Look", [Shortcut(.space), cmd("y")], .file),
        item(.fullScreenPreview, "Quick Look Full Screen", [cmd("y", .option)], .file),
        item(.moveToTrash, "Move to Trash", [Shortcut(.delete, .command)], .file, context: .notTrash, group: true),
        item(.putBack, "Put Back", [Shortcut(.delete, .command)], .file, context: .trash),
        item(.emptyTrash, "Empty Trash…", [Shortcut(.delete, [.command, .shift])], .file),
        item(.emptyTrashNow, "Empty Trash Without Asking", [Shortcut(.delete, [.command, .shift, .option])], .file),
        item(.eject, "Eject", [cmd("e")], .file, context: .notArchive, group: true),
        item(.extract, "Extract Selected", [cmd("e")], .file, context: .archive),
        item(.extractTo, "Extract To…", [cmd("e", .option)], .file, context: .archive),
        item(.share, "Share…", [cmd("s", .shift)], .file, group: true),
        item(.airDrop, "Send with AirDrop…", [cmd("r", .control)], .file),
        item(.copyPath, "Copy as Pathname", [cmd("c", .option)], .file),
        item(.addToSidebar, "Add to Sidebar", [cmd("t", .control)], .file),
        item(.showAllInSidebar, "Show All in Sidebar", [cmd("s", [.control, .option])], .file),
        item(.tagRed, "Red", [Shortcut(.character("1"), .control)], .file, group: true, submenu: "Tags"),
        item(.tagOrange, "Orange", [Shortcut(.character("2"), .control)], .file, submenu: "Tags"),
        item(.tagYellow, "Yellow", [Shortcut(.character("3"), .control)], .file, submenu: "Tags"),
        item(.tagGreen, "Green", [Shortcut(.character("4"), .control)], .file, submenu: "Tags"),
        item(.tagBlue, "Blue", [Shortcut(.character("5"), .control)], .file, submenu: "Tags"),
        item(.tagPurple, "Purple", [Shortcut(.character("6"), .control)], .file, submenu: "Tags"),
        item(.tagGray, "Gray", [Shortcut(.character("7"), .control)], .file, submenu: "Tags"),
        item(.removeTags, "Remove Tags", [Shortcut(.character("0"), .control)], .file, submenu: "Tags"),
        item(.editTags, "Edit Tags…", [cmd("e", .control)], .file, submenu: "Tags"),
        item(.find, "Find", [cmd("f"), cmd("n", .option)], .file, group: true),
        item(.saveSearch, "Save Search…", [cmd("f", .option)], .file),
        item(.cleanClutter, "Clean .DS_Store Files…", [cmd("k", .control)], .file),
    ]

    static let edit: [CommandSpec] = [
        item(.undo, "Undo", [cmd("z")], .edit),
        item(.redo, "Redo", [cmd("z", .shift)], .edit),
        item(.cut, "Cut", [cmd("x")], .edit, group: true),
        item(.copy, "Copy", [cmd("c")], .edit),
        item(.paste, "Paste", [cmd("v")], .edit),
        item(.moveHere, "Move Item Here", [cmd("v", .option)], .edit),
        item(.selectAll, "Select All", [cmd("a")], .edit, group: true),
        item(.deselectAll, "Deselect All", [cmd("a", .option)], .edit),
    ]

    static let view: [CommandSpec] = [
        item(.viewIcons, "as Icons", [cmd("1")], .view),
        item(.viewList, "as List", [cmd("2")], .view),
        item(.viewColumns, "as Columns", [cmd("3")], .view),
        item(.viewGallery, "as Gallery", [cmd("4")], .view),
        item(.viewPanes, "as Panes", [cmd("5")], .view),
        item(.sortName, "Name", [cmd("1", [.control, .option])], .view, group: true, submenu: "Sort By"),
        item(.sortKind, "Kind", [cmd("2", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortLastOpened, "Date Last Opened", [cmd("3", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortAdded, "Date Added", [cmd("4", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortModified, "Date Modified", [cmd("5", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortCreated, "Date Created", [cmd("6", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortSize, "Size", [cmd("7", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortTags, "Tags", [cmd("8", [.control, .option])], .view, submenu: "Sort By"),
        item(.sortManual, "Manual", [cmd("0", [.control, .option])], .view, submenu: "Sort By"),
        item(.groupNone, "None", [cmd("0", .control)], .view, group: true, submenu: "Group By"),
        item(.groupKind, "Kind", [cmd("2", .control)], .view, submenu: "Group By"),
        item(.keepFoldersOnTop, "Keep Folders on Top", [cmd("9", [.control, .option])], .view),
        item(.showViewOptions, "Show View Options", [cmd("j")], .view, group: true),
        item(.rememberView, "Remember View for This Folder", [cmd("j", .control)], .view),
        item(.useAsDefaultView, "Use as Default View", [cmd("j", .option)], .view),
        item(.toggleHidden, "Show Hidden Files", [cmd(".", .shift)], .view, group: true),
        item(.togglePreview, "Show Preview", [cmd("p", .shift)], .view),
        item(.toggleInspector, "Show Inspector", [cmd("i", .option)], .view),
        item(.toggleSidebar, "Show Sidebar", [cmd("s", .option)], .view),
        item(.toggleStatusBar, "Show Status Bar", [cmd("/")], .view),
        item(.toggleToolbar, "Show Toolbar", [cmd("t", .option)], .view),
        item(.togglePathBar, "Show Path Bar", [cmd("p", .option)], .view),
        item(.biggerIcons, "Bigger Icons", [cmd("=")], .view, group: true),
        item(.smallerIcons, "Smaller Icons", [cmd("-")], .view),
        item(.showTransfers, "Show Transfers", [cmd("j", .shift)], .view),
    ]

    static let go: [CommandSpec] = [
        item(.back, "Back", [cmd("[")], .go),
        item(.forward, "Forward", [cmd("]")], .go),
        item(.enclosingFolder, "Enclosing Folder", [Shortcut(.up, .command)], .go),
        item(.enclosingFolderInNewWindow, "Enclosing Folder in New Window", [Shortcut(.up, [.command, .control])], .go),
        item(.openSelection, "Open Selection", [Shortcut(.down, .command)], .go),
        item(.goRecents, "Recents", [cmd("f", .shift)], .go, group: true),
        item(.goDocuments, "Documents", [cmd("o", .shift)], .go),
        item(.goDesktop, "Desktop", [cmd("d", .shift)], .go),
        item(.goDownloads, "Downloads", [cmd("l", .option)], .go),
        item(.goHome, "Home", [cmd("h", .shift)], .go),
        item(.goComputer, "Computer", [cmd("c", .shift)], .go),
        item(.goAirDrop, "AirDrop", [cmd("r", .shift)], .go),
        item(.goNetwork, "Network", [cmd("k", .shift)], .go),
        item(.goICloud, "iCloud Drive", [cmd("i", .shift)], .go),
        item(.goApplications, "Applications", [cmd("a", .shift)], .go),
        item(.goUtilities, "Utilities", [cmd("u", .shift)], .go),
        item(.goLibrary, "Library", [cmd("l", .shift)], .go),
        item(.goDrive, "Google Drive", [cmd("g", .control)], .go),
        item(.goTrash, "Trash", [cmd("t", [.shift, .option])], .go),
        item(.goToFolder, "Go to Folder…", [cmd("g", .shift)], .go, group: true),
        item(.connectToServer, "Connect to Server…", [cmd("k")], .go),
    ]

    static let panes: [CommandSpec] = [
        item(.nextPane, "Next Pane", [Shortcut(.tab)], .panes),
        item(.previousPane, "Previous Pane", [Shortcut(.tab, .shift)], .panes),
        item(.copyToNextPane, "Copy to Next Pane", [Shortcut(.function(5))], .panes, group: true),
        item(.moveToNextPane, "Move to Next Pane", [Shortcut(.function(6))], .panes),
        item(.onePane, "One Pane", [cmd("1", .option)], .panes, group: true),
        item(.twoPanes, "Two Panes", [cmd("2", .option)], .panes),
        item(.threePanes, "Three Panes", [cmd("3", .option)], .panes),
        item(.fourPanes, "Four Panes", [cmd("4", .option)], .panes),
        item(.pinWindow, "Pin Window", [cmd("p", .control)], .panes, group: true),
        item(.saveWorkspace, "Save Workspace…", [cmd("w", .control)], .panes),
    ]

    static let tools: [CommandSpec] = [
        item(.openTerminal, "Open in Ghostty", [tool("t")], .tools),
        item(.openClaude, "Open Claude Code Here", [tool("a")], .tools),
        item(.transcodeVideo, "Video", [tool("1")], .tools, group: true, submenu: "Transcode"),
        item(.transcodePNG, "PNG", [tool("2")], .tools, submenu: "Transcode"),
        item(.transcodeJPEG, "JPEG", [tool("3")], .tools, submenu: "Transcode"),
        item(.transcodePDF, "PDF", [tool("4")], .tools, submenu: "Transcode"),
        item(.transcodeText, "Text", [tool("5")], .tools, submenu: "Transcode"),
    ]
}
