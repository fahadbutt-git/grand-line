import AppKit
import BrowserKit

/// Keeps a text field's keys its own while it is edited (BrowserKit's
/// `TextAction` and `Shortcut.belongsToTextFields`): Cut, Copy, Paste, Select
/// All, Undo and Redo go to the text, and file commands on typing keys wait.
@MainActor
enum TextFieldGuard {
    /// The text being typed in, when the keys are with a live editor
    /// (`TextFocus`). A field editor left behind by a field that has gone does
    /// not count: the keys then belong to the files.
    static func editor(in window: NSWindow?) -> NSText? {
        guard let window, let text = window.firstResponder as? NSText else { return nil }
        let field: NSView? = text.isFieldEditor ? (text.delegate as? NSView) : nil
        let live = TextFocus.isLive(
            editorInWindow: text.window === window,
            editorInView: text.superview != nil,
            fieldOnScreen: field.map { $0.window === window && !$0.isHiddenOrHasHiddenAncestor }
        )
        return live ? text : nil
    }

    /// A field on screen is being typed in.
    static func isTyping(in window: NSWindow?) -> Bool {
        editor(in: window) != nil
    }

    /// The first responder by kind, for the log: "FileTableView", "text field
    /// (live)", "text field left behind by a closed field".
    static func describeKeys(in window: NSWindow?) -> String {
        guard let window else { return "no window" }
        guard let responder = window.firstResponder else { return "nothing" }
        if responder is NSText {
            return isTyping(in: window) ? "a text field being edited" : "a text editor left behind by a closed field"
        }
        return String(describing: type(of: responder))
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
