import AppKit
import BrowserKit
import FileKit

/// The path bar's field as one keyboard target (`Omnibar`): a path with Tab
/// completion, a filter on the folder as you type, `?` to search with the
/// search field's scopes, `>` to run a command. Shift+Cmd+G opens it as
/// Finder's Go to Folder; Option+Cmd+G opens it as a filter.
extension BrowserModel {
    var omnibarMode: Omnibar.Mode {
        Omnibar.mode(for: pathText, origin: omnibarOrigin, aliases: pathAliases)
    }

    /// Option+Cmd+G: the field, holding the folder's filter.
    func beginFilter() {
        omnibarOrigin = .filter
        pathText = focused.state.filter
        pathProblem = nil
        editingPath = true
    }

    /// Every change of the field's text: a filter applies at once.
    func omnibarChanged() {
        pathProblem = nil
        if case .filter(let text) = omnibarMode {
            focused.setFilter(text)
        } else if omnibarOrigin == .filter, !focused.state.filter.isEmpty {
            focused.setFilter("")
        }
    }

    /// `?query`, as typed: the same search the search field runs.
    func omnibarSearch(_ query: String) {
        searchText = query
        search(query, scope: nil)
    }

    /// Return. `command` is the row picked in the command list.
    func omnibarSubmit(command: BrowserCommand? = nil) {
        switch omnibarMode {
        case .path, .folderName:
            submitPath(pathText, fuzzyMatch: nil)
        case .filter:
            // The filter stays; the keys go back to the list.
            endPathEditing()
        case .search(let query):
            endPathEditing()
            if !query.isEmpty { omnibarSearch(query) }
        case .command(let text):
            let chosen = command ?? commandMatches(text).first?.command
            endPathEditing()
            guard let chosen else {
                NSSound.beep()
                return
            }
            perform(chosen)
        }
    }

    /// Escape: a filter or a search typed here ends with the field.
    func omnibarCancel() {
        switch omnibarMode {
        case .filter: focused.setFilter("")
        case .search(let query) where !query.isEmpty: endSearch()
        default: break
        }
        endPathEditing()
    }

    func clearFilter(in pane: PaneModel) {
        pane.setFilter("")
    }

    /// Commands that apply here, matching the typed words.
    func commandMatches(_ text: String) -> [Omnibar.CommandMatch] {
        Omnibar.commands(matching: text) { command in
            command != .filterFolder && command != .goToFolder && self.isEnabled(command)
        }
    }

    /// The folders a typed path could go on to, for the list under the field.
    func pathCompletions(_ text: String) -> [URL] {
        let current = focused.location.diskFolder ?? services.paths.home
        return PathInput.completions(
            for: text, relativeTo: current, home: services.paths.home, aliases: pathAliases, children: FolderReader.subfolderNames
        )
    }
}
