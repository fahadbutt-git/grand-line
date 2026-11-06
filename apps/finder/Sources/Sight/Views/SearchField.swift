import AppKit
import SwiftUI

/// The query field: an NSTextField, so the panel can focus it and keys reach
/// it first. Its text, placeholder and insertion point are the system's own
/// colours, so it reads as Spotlight's field in Light and in Dark.
struct SearchField: NSViewRepresentable {
    @ObservedObject var model: SearchModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typo.fieldNS
        field.textColor = .labelColor
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.field = field
        placeholder(field, context.coordinator)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.text { field.stringValue = model.text }
        placeholder(field, context.coordinator)
    }

    /// The placeholder, set again only when it changes, never on each keystroke.
    private func placeholder(_ field: NSTextField, _ coordinator: Coordinator) {
        guard coordinator.placeholder != model.placeholder else { return }
        coordinator.placeholder = model.placeholder
        field.placeholderAttributedString = NSAttributedString(
            string: model.placeholder,
            attributes: [.foregroundColor: NSColor.placeholderTextColor, .font: Typo.fieldNS]
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel
        /// The placeholder the field last got.
        var placeholder: String?

        init(model: SearchModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let text = field.stringValue
            MainActor.assumeIsolated { model.setText(text) }
        }
    }
}
