import Foundation

/// Right arrow on a row (LaunchBar, Alfred, Listary): a folder opens in the
/// field as a path, so its contents list and the arrow keeps going deeper;
/// any other row with more than one thing to do opens its actions.
public enum DrillIn: Sendable, Equatable {
    /// Put this path query in the field ("~/Documents/").
    case browse(String)
    /// Open the action panel.
    case actions

    /// What Right arrow does on `row`, or nil when it should move the cursor as usual.
    public static func target(for row: LaunchResult?, paths: GrandLinePaths = GrandLinePaths()) -> DrillIn? {
        guard let row, !row.isFallback else { return nil }
        if case .file(let path, let isFolder) = ResultKind.of(row), isFolder {
            return .browse(paths.abbreviate(path) + "/")
        }
        return ActionPanel.actions(for: row).count > 1 ? .actions : nil
    }
}

/// A modifier held down while the window has the keys: the selected row's
/// subtitle and the footer say what Return does with it (Alfred).
public enum HeldModifier: Sendable, Equatable {
    case none
    /// Command: Command+Return runs the second action.
    case command
    /// Option: Option+Return runs the alternate.
    case option

    public init(command: Bool, option: Bool, shift: Bool = false, control: Bool = false) {
        if shift || control || (command && option) {
            self = .none
        } else if command {
            self = .command
        } else if option {
            self = .option
        } else {
            self = .none
        }
    }
}

public extension ActionPanel {
    /// Option+Return: the row's copy that is not already its Return or
    /// Command+Return (the path of a file, a link's URL, the answer with its
    /// unit, an app's name), or nil when it has none.
    static func alternate(for result: LaunchResult) -> LaunchAction? {
        let taken = Set(result.actions.prefix(2).map(\.command))
        return actions(for: result).first { action in
            guard !taken.contains(action.command), action.confirmation == nil else { return false }
            if case .copyText = action.command { return true }
            return false
        }
    }

    /// The action a held modifier would run with Return.
    static func action(for result: LaunchResult, held: HeldModifier) -> LaunchAction? {
        switch held {
        case .none: return result.primary
        case .command: return result.secondary
        case .option: return alternate(for: result)
        }
    }
}

/// What the selected row's subtitle says while a modifier is held.
public enum ModifierPreview {
    public static func subtitle(for result: LaunchResult, held: HeldModifier) -> String? {
        guard held != .none, let action = ActionPanel.action(for: result, held: held) else { return nil }
        let keys = held == .command ? "\u{2318}\u{21B5}" : "\u{2325}\u{21B5}"
        return keys + " " + action.title
    }
}
