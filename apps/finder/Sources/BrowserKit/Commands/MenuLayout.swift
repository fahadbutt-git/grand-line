import Foundation

/// The menu bar, built from the catalog so no command is left out of it.
public enum MenuEntry: Sendable {
    case separator
    case command(CommandSpec)
    case submenu(String, [CommandSpec])
}

public enum MenuLayout {
    public static func entries(for group: MenuGroup) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        var pendingTitle: String?
        var pending: [CommandSpec] = []

        func flush() {
            if let title = pendingTitle, !pending.isEmpty { entries.append(.submenu(title, pending)) }
            pendingTitle = nil
            pending = []
        }

        for spec in CommandCatalog.all where spec.menu == group {
            let continuesSubmenu = spec.submenu != nil && spec.submenu == pendingTitle
            if !continuesSubmenu {
                flush()
                if spec.startsGroup, !entries.isEmpty { entries.append(.separator) }
            }
            if let submenu = spec.submenu {
                pendingTitle = submenu
                pending.append(spec)
            } else {
                entries.append(.command(spec))
            }
        }
        flush()
        return entries
    }

    /// Every command reachable from the menu bar, for the tests.
    public static func allCommands() -> [BrowserCommand] {
        MenuGroup.allCases.flatMap { group in
            entries(for: group).flatMap { entry -> [BrowserCommand] in
                switch entry {
                case .separator: return []
                case .command(let spec): return [spec.command]
                case .submenu(_, let specs): return specs.map(\.command)
                }
            }
        }
    }
}
