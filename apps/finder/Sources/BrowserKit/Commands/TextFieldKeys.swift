import Foundation

/// The edit commands a text field does itself. While a field is being edited
/// (renaming, the path bar, search), these act on its text, not on files.
public enum TextAction: Sendable, Equatable {
    case undo, redo, cut, copy, paste, selectAll
}

public extension BrowserCommand {
    var textAction: TextAction? {
        switch self {
        case .undo: return .undo
        case .redo: return .redo
        case .cut: return .cut
        case .copy: return .copy
        case .paste: return .paste
        case .selectAll: return .selectAll
        default: return nil
        }
    }
}

public extension Shortcut {
    /// Keys a text field needs while you type: plain keys, Command+Delete (delete
    /// to the start of the line) and Command or Option with an arrow (move the
    /// caret). Menu items on these keys step aside while a field is edited.
    var belongsToTextFields: Bool {
        if isPlain { return true }
        if modifiers.contains(.control) { return false }
        switch key {
        case .delete, .up, .down, .left, .right: return true
        default: return false
        }
    }
}

/// Whether a text editor that has the keys is really being typed in. A field
/// editor can stay the window's first responder after its field has gone (the
/// path bar's field closed by Return, a row's name reloaded away mid-rename):
/// Cut, Copy, Paste and Select All sent to it went nowhere, so Cmd+C and Cmd+V
/// never reached the files. Only an editor in the window, in a view, whose
/// field (for a field editor) is still on screen in that window, counts.
public enum TextFocus {
    public static func isLive(editorInWindow: Bool, editorInView: Bool, fieldOnScreen: Bool?) -> Bool {
        editorInWindow && editorInView && (fieldOnScreen ?? true)
    }
}
