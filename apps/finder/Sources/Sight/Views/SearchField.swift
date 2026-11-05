import AppKit
import SwiftUI
import ThemeKit

/// The query field: an NSTextField, so the panel can focus it and keys reach it first.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: SearchModel
    let theme: Theme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typo.fieldNS
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.field = field
        style(field, context.coordinator)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.text { field.stringValue = model.text }
        style(field, context.coordinator)
    }

    /// Colours and the placeholder, set again only when the theme or the
    /// placeholder changes, never on each keystroke.
    private func style(_ field: NSTextField, _ coordinator: Coordinator) {
        let key = "\(theme.strong.hex) \(theme.faint.hex) \(theme.accent.hex) \(model.placeholder)"
        if let editor = field.currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor(theme.accent)
        }
        guard coordinator.styled != key else { return }
        coordinator.styled = key
        field.textColor = NSColor(theme.strong)
        field.placeholderAttributedString = NSAttributedString(
            string: model.placeholder,
            attributes: [.foregroundColor: NSColor(theme.faint), .font: Typo.fieldNS]
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel
        /// What the field was last styled with.
        var styled = ""

        init(model: SearchModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let text = field.stringValue
            MainActor.assumeIsolated { model.setText(text) }
        }
    }
}
