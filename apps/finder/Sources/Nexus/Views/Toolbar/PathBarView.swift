import AppKit
import BrowserKit
import SwiftUI

/// The path bar (R5): clickable folders, or the omnibar field. Shift+Cmd+G
/// opens it as Finder's Go to Folder (a path, Tab completes, or a folder name
/// to find in the index); Option+Cmd+G opens it as a filter on the folder.
/// In either, `?words` searches and `>words` runs a command.
struct PathBarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @Local private var rows: [OmnibarRow] = []
    @Local private var highlight = 0
    /// Arrow keys moved through the list, so Return takes the row, not the text.
    @Local private var moved = false

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
                if pane.state.isFlat {
                    Chip(title: "and subfolders", symbol: "list.bullet.indent", palette: palette, isOn: true) { model.perform(.toggleFlatView) }
                        .help("Flat view  ⌃⌥⌘F")
                        .accessibilityIdentifier("nexus.flat")
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
        let mode = model.omnibarMode
        return HStack(spacing: 6) {
            OmnibarBadge(mode: mode, palette: palette)
            PathField(text: $model.pathText, placeholder: Omnibar.Mode.placeholder(model.omnibarOrigin), palette: palette,
                      onSubmit: submit,
                      onCancel: { model.omnibarCancel() },
                      onTab: complete,
                      onMove: move)
            if let problem = model.pathProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("nexus.path.problem")
            } else if case .filter(let text) = mode, !text.isEmpty {
                Text("\(pane.items.count) of \(pane.state.unfilteredCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(palette.dim)
                    .fixedSize()
                    .accessibilityIdentifier("nexus.filter.count")
            }
        }
        .padding(.horizontal, 8)
        .onChange(of: model.pathText) { _, _ in
            highlight = 0
            moved = false
            model.omnibarChanged()
        }
        .task(id: model.pathText) { await refreshRows() }
        .popover(isPresented: .constant(model.editingPath && !rows.isEmpty), arrowEdge: .bottom) { list }
    }

    /// The list under the field: matching folders for a path or a name, or
    /// matching commands. A search starts once typing pauses.
    private func refreshRows() async {
        switch model.omnibarMode {
        case .path(let text):
            rows = model.pathCompletions(text).prefix(10).map { .folder($0) }
        case .command(let text):
            rows = model.commandMatches(text).map { .command($0) }
        case .folderName(let name):
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let found = await model.folderMatches(name)
            guard !Task.isCancelled else { return }
            rows = found.map { .folder($0) }
        case .search(let query):
            rows = []
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, !query.isEmpty, model.editingPath else { return }
            model.omnibarSearch(query)
        case .filter:
            rows = []
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button { pick(index) } label: { label(for: row, highlighted: index == highlight) }
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .accessibilityIdentifier("nexus.omnibar.list")
    }

    @ViewBuilder private func label(for row: OmnibarRow, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            switch row {
            case .folder(let url):
                Image(systemName: "folder").foregroundStyle(palette.accent).frame(width: 16)
                Text(url.lastPathComponent).foregroundStyle(palette.text).lineLimit(1)
                Spacer(minLength: 8)
                Text(PathSegments.editableText(for: url.deletingLastPathComponent(), home: model.services.paths.home))
                    .foregroundStyle(palette.dim).lineLimit(1).truncationMode(.head)
            case .command(let match):
                Image(systemName: "chevron.right").foregroundStyle(palette.accent).frame(width: 16)
                Text(match.title).foregroundStyle(palette.text).lineLimit(1)
                Spacer(minLength: 8)
                if !match.shortcut.isEmpty { KeyCap(text: match.shortcut, palette: palette) }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 6)
        .frame(width: 400, height: 26, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? palette.selection.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
    }

    /// Return: a row picked with the arrows (or the best folder for a name),
    /// else what the text asks for.
    private func submit() {
        let row = rows.indices.contains(highlight) ? rows[highlight] : nil
        switch (model.omnibarMode, row) {
        case (.path, .folder(let url)?) where moved:
            model.submitPath(url.path, fuzzyMatch: nil)
        case (.folderName, .folder(let url)?):
            model.submitPath(model.pathText, fuzzyMatch: url)
        case (.command, .command(let match)?):
            model.omnibarSubmit(command: match.command)
        default:
            model.omnibarSubmit()
        }
    }

    private func pick(_ index: Int) {
        highlight = index
        moved = true
        submit()
    }

    /// Tab: completes a path; on a folder name or a command it takes the row.
    private func complete() {
        switch model.omnibarMode {
        case .path:
            if moved, rows.indices.contains(highlight), case .folder(let url) = rows[highlight] {
                model.pathText = PathSegments.editableText(for: url, home: model.services.paths.home) + "/"
            } else if let completed = model.completePath(model.pathText) {
                model.pathText = completed
            }
        case .folderName:
            if rows.indices.contains(highlight), case .folder(let url) = rows[highlight] {
                model.pathText = PathSegments.editableText(for: url, home: model.services.paths.home) + "/"
            }
        case .command:
            if rows.indices.contains(highlight), case .command(let match) = rows[highlight] {
                model.pathText = ">" + match.title
            }
        case .filter, .search:
            break
        }
    }

    /// Up and Down move through the list; false lets the field have the key.
    private func move(_ step: Int) -> Bool {
        guard !rows.isEmpty else { return false }
        highlight = min(max(0, highlight + step), rows.count - 1)
        moved = true
        return true
    }
}

/// A row in the omnibar's list.
enum OmnibarRow {
    case folder(URL)
    case command(Omnibar.CommandMatch)

    var id: String {
        switch self {
        case .folder(let url): return "folder:" + url.path
        case .command(let match): return "command:" + match.command.rawValue
        }
    }
}

/// What the field is doing, at its leading edge: a filter is an outlined
/// chip, a search a filled one, so the two never look alike.
struct OmnibarBadge: View {
    let mode: Omnibar.Mode
    let palette: Palette

    var body: some View {
        let filled: Bool = {
            if case .search = mode { return true }
            return false
        }()
        HStack(spacing: 3) {
            Image(systemName: mode.symbol).font(.system(size: 10, weight: .semibold))
            Text(mode.badge).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(filled ? palette.selectionText : palette.accent)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 5).fill(filled ? palette.accent : palette.chip.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.accent.opacity(filled ? 0 : 0.6), lineWidth: 0.5))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.badge)
        .accessibilityIdentifier("nexus.omnibar.mode")
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
    /// Up (-1) and Down (+1); returns whether the key was used.
    var onMove: (Int) -> Bool = { _ in false }

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
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
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
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMove(1)
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
