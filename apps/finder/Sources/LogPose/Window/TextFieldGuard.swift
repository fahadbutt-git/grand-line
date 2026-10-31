import AppKit
import BrowserKit

/// Keeps a text field's keys its own while it is edited (BrowserKit's
/// `TextAction` and `Shortcut.belongsToTextFields`): Cut, Copy, Paste, Select
/// All, Undo and Redo go to the text, and file commands on typing keys wait.
@MainActor
enum TextFieldGuard {
    static func editor(in window: NSWindow?) -> NSText? {
        window?.firstResponder as? NSText
    }

    /// Runs a text command on the field being edited. False when no field is
    /// being edited or the command is not a text command.
    static func forward(_ command: BrowserCommand, in window: NSWindow?) -> Bool {
        guard let editor = editor(in: window), let action = command.textAction else { return false }
        switch action {
        case .undo: editor.undoManager?.undo()
        case .redo: editor.undoManager?.redo()
        case .cut: editor.cut(nil)
        case .copy: editor.copy(nil)
        case .paste: editor.paste(nil)
        case .selectAll: editor.selectAll(nil)
        }
        return true
    }

    /// Nil when no field is being edited; otherwise whether the item stays
    /// enabled. The item's tag is the index of its shortcut in the spec.
    static func validate(_ item: NSMenuItem, _ command: BrowserCommand, in window: NSWindow?) -> Bool? {
        guard let editor = editor(in: window) else { return nil }
        switch command.textAction {
        case .undo?: return editor.undoManager?.canUndo ?? false
        case .redo?: return editor.undoManager?.canRedo ?? false
        case .some: return true
        case nil: break
        }
        let shortcuts = CommandCatalog.spec(command).shortcuts
        guard shortcuts.indices.contains(item.tag) else { return true }
        return !shortcuts[item.tag].belongsToTextFields
    }
}
