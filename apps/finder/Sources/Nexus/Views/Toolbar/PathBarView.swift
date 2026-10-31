import AppKit
import BrowserKit
import SwiftUI

/// The path bar (R5): clickable folders, or a field after Cmd+Shift+G (Finder's
/// Go to Folder) that takes a path (Tab completes) or a folder name to find in
/// the index.
struct PathBarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @Local private var matches: [URL] = []

    var body: some View {
        Group {
            if model.editingPath { editor } else { crumbs }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(palette.field))
    }

    private var crumbs: some View {
        HStack(spacing: 3) {
            if let folder = pane.location.diskFolder {
                let segments = PathSegments.segments(for: folder, home: model.services.paths.home, aliases: model.pathAliases)
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 { Text("›").font(.system(size: 12)).foregroundStyle(palette.faint) }
                    Button(segment.title) { pane.go(.folder(segment.url)) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: index == segments.count - 1 ? .semibold : .regular))
                        .foregroundStyle(index == segments.count - 1 ? palette.strong : palette.dim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(index == segments.count - 1 ? 1 : 0)
                }
                if case .archive(_, let entry) = pane.location, !entry.isEmpty {
                    Text("› " + entry.replacingOccurrences(of: "/", with: " › "))
                        .font(.system(size: 13)).foregroundStyle(palette.strong).lineLimit(1).truncationMode(.head)
                }
            } else {
                Text(pane.location.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.strong).lineLimit(1)
            }
            Spacer(minLength: 6)
            KeyCap(text: "⇧⌘G", palette: palette)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.beginPathEditing() }
    }

    private var editor: some View {
        HStack(spacing: 6) {
            PathField(text: $model.pathText, placeholder: "Path or folder name", palette: palette,
                      onSubmit: { model.submitPath(model.pathText, fuzzyMatch: matches.first) },
                      onCancel: { model.endPathEditing() },
                      onTab: { if let completed = model.completePath(model.pathText) { model.pathText = completed } })
            if let problem = model.pathProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nexus.path.problem")
            }
        }
        .padding(.horizontal, 8)
        .onChange(of: model.pathText) { _, _ in model.pathProblem = nil }
        .task(id: model.pathText) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            matches = await model.folderMatches(model.pathText)
        }
        .popover(isPresented: .constant(model.editingPath && !matches.isEmpty && !model.pathText.contains("/")), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matches, id: \.self) { url in
                    Button { model.submitPath(model.pathText, fuzzyMatch: url) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder").foregroundStyle(palette.accent).frame(width: 16)
                            Text(url.lastPathComponent).foregroundStyle(palette.text).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(PathSegments.editableText(for: url.deletingLastPathComponent(), home: model.services.paths.home))
                                .foregroundStyle(palette.dim).lineLimit(1).truncationMode(.head)
                        }
                        .font(.system(size: 13))
                        .frame(width: 380, height: 26, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }
}

/// The Go to Folder field. An AppKit text field, so it takes the keys the
/// moment it appears (a SwiftUI focus request made on appear can be lost, and
/// the typing then lands in the search field), and Return, Escape and Tab
/// reach it directly.
struct PathField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let palette: Palette
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onTab: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusingTextField {
        let field = FocusingTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("nexus.path")
        return field
    }

    func updateNSView(_ field: FocusingTextField, context: Context) {
        context.coordinator.parent = self
        field.textColor = NSColor(palette.strong)
        guard field.stringValue != text else { return }
        field.stringValue = text
        // A completion (Tab) leaves the caret at the end, ready for more.
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PathField

        init(_ parent: PathField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = control.stringValue
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab()
                return true
            default:
                return false
            }
        }
    }
}

/// Becomes the first responder as soon as it is in a window, with its text selected.
final class FocusingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            if window.makeFirstResponder(self) { self.currentEditor()?.selectAll(nil) }
        }
    }
}
