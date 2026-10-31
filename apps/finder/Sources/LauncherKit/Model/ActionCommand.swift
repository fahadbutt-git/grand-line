import Foundation

/// What a file action does to every file it is given: one file from a row,
/// all of the file buffer, or the Finder or Nexus selection.
public enum FileVerb: String, Codable, Hashable, Sendable, CaseIterable {
    case open
    /// Shows them selected in Nexus.
    case reveal
    case copyFiles
    /// Asks for a folder and moves them there; nothing is ever replaced.
    case moveTo
    case airDrop
    /// Moves them to the Trash (Put Back works); nothing is ever deleted.
    case trash
    case quickLook
}

/// What an action does. LauncherKit only describes it; the app carries it out.
public enum ActionCommand: Codable, Hashable, Sendable {
    /// A file, folder or URL with its default app. Folders open in Nexus.
    case open(String)
    /// A URL in a given app (bundle id), or the default browser when nil.
    case openURL(String, bundleID: String?)
    /// Asks which app to open the file with.
    case openWith(String)
    /// Shows the item selected in its folder, in Nexus.
    case reveal(String)
    case quickLook(String)
    case copyText(String)
    case copyFile(String)
    /// Copies the text and pastes it into the app that was in front.
    case paste(String)
    /// Types the text into the app that was in front, key by key (for Espanso triggers).
    case typeText(String)
    /// Presses a key combination once the window is gone, such as another
    /// app's global shortcut (needs Accessibility).
    case pressKeys(KeyShortcut)
    /// Asks for a folder and moves the file there.
    case moveTo(String)
    case airDrop(String)
    /// Starts a program and does not wait for it.
    case run(String, arguments: [String])
    /// Runs a line in bash with the Grand Line commands on the PATH, as the menu does.
    case shell(String)
    /// Replaces the query, to complete it or enter a provider.
    case setQuery(String)
    /// Clicks an item in the front app's menu bar.
    case pressMenuItem(pid: Int32, path: [String])
    /// Quits a process (SIGTERM through NSRunningApplication), or force quits it.
    case quit(pid: Int32, force: Bool)
    /// Opens a word in the Dictionary app.
    case lookUp(String)
    /// Adds the row to the favourites, or removes it.
    case toggleFavourite
    /// A file action on several files at once.
    case files(FileVerb, [String])
    /// Adds files to the file buffer (Command+B), or takes them out.
    case buffer([String])
    /// Empties the file buffer.
    case clearBuffer
    /// Creates an empty file (never over an existing one) and shows it in Nexus.
    case createFile(String)
    /// Runs a script command again with the chosen row's value (ScriptCommands).
    case script(path: String, value: String)
}
