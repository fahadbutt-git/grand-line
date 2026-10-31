import Foundation

/// Finds the command for a key press (R4): Return opens, F2 renames, Cmd+Up goes
/// up, Space previews, Tab moves between panes, F5 and F6 copy and move.
public enum KeyMap {
    static let table: [Shortcut: [CommandSpec]] = {
        var table: [Shortcut: [CommandSpec]] = [:]
        for spec in CommandCatalog.all {
            for shortcut in spec.shortcuts { table[shortcut, default: []].append(spec) }
        }
        return table
    }()

    public static func command(for shortcut: Shortcut, inArchive: Bool = false, inTrash: Bool = false) -> BrowserCommand? {
        table[shortcut]?.first { $0.context.matches(inArchive: inArchive, inTrash: inTrash) }?.command
    }

    /// Shortcuts that two commands claim in the same place. Empty when the map is sound.
    public static func conflicts() -> [Shortcut: [BrowserCommand]] {
        var found: [Shortcut: [BrowserCommand]] = [:]
        for (shortcut, specs) in table where specs.count > 1 {
            for (archive, trash) in [(false, false), (true, false), (false, true), (true, true)] {
                let matching = specs.filter { $0.context.matches(inArchive: archive, inTrash: trash) }
                if matching.count > 1 { found[shortcut] = matching.map(\.command) }
            }
        }
        return found
    }
}
