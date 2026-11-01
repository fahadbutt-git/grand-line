import Foundation

/// What a key does in the search window. Keys that are not listed type into the field.
public enum KeyCommand: Sendable, Equatable {
    case moveUp
    case moveDown
    case pageUp
    case pageDown
    /// Return: the row's first action.
    case primary
    /// Command+Return: the row's second action (Show in Nexus for files).
    case secondary
    /// Option+Return: the row's alternate, a copy (path, URL, answer, name).
    case alternate
    /// Right arrow with the cursor at the end of the field: into a folder, or
    /// the actions of any other row.
    case drillIn
    /// Command+K: the action panel.
    case actions
    /// Command+1…9: run that row.
    case runRow(Int)
    case escape
    /// Tab: complete the query from the selected row.
    case complete
    /// Command+Y: the Quick Look preview pane.
    case togglePreview
    /// Command+C with nothing selected in the field: copy the row's path or text.
    case copy
    /// Command+B: put the selected file in the file buffer, or take it out.
    case toggleBuffer
    /// Command+Shift+C, Command+O and other shortcuts an action lists.
    case shortcut(KeyShortcut)

    public static func command(for key: KeyPress) -> KeyCommand? {
        let plain = !key.command && !key.option && !key.control
        switch key.keyCode {
        case KeyPress.Code.up where plain: return .moveUp
        case KeyPress.Code.down where plain: return .moveDown
        case KeyPress.Code.pageUp: return .pageUp
        case KeyPress.Code.pageDown: return .pageDown
        case KeyPress.Code.returnKey, KeyPress.Code.enter:
            if key.command && !key.shift && !key.option { return .secondary }
            if key.option && !key.command && !key.shift && !key.control { return .alternate }
            if plain && !key.shift { return .primary }
        case KeyPress.Code.escape: return .escape
        case KeyPress.Code.tab where plain && !key.shift: return .complete
        case KeyPress.Code.right where plain && !key.shift: return .drillIn
        default: break
        }
        if key.control && !key.command, key.characters == "n" { return .moveDown }
        if key.control && !key.command, key.characters == "p" { return .moveUp }
        guard key.command else { return nil }
        if !key.shift && !key.option && !key.control {
            switch key.characters {
            case "k": return .actions
            case "y": return .togglePreview
            case "c": return .copy
            case "b": return .toggleBuffer
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": return .runRow(Int(key.characters)!)
            // Editing keys stay with the text field.
            case "a", "v", "x", "z": return nil
            default: break
            }
        }
        guard let character = key.characters.first, character.isLetter || character.isNumber else { return nil }
        return .shortcut(KeyShortcut(String(character), command: true, shift: key.shift, option: key.option, control: key.control))
    }
}
