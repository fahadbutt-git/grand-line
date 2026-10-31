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
        field.font = .systemFont(ofSize: 17)
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        model.field = field
        style(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != model.text { field.stringValue = model.text }
        style(field)
    }

    private func style(_ field: NSTextField) {
        field.textColor = NSColor(theme.strong)
        field.placeholderAttributedString = NSAttributedString(
            string: "Search apps, files, commands. / for prefixes",
            attributes: [.foregroundColor: NSColor(theme.faint), .font: NSFont.systemFont(ofSize: 17)]
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel

        init(model: SearchModel) { self.model = model }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let text = field.stringValue
            MainActor.assumeIsolated { model.setText(text) }
        }
    }
}
