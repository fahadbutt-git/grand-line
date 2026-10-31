import BrowserKit
import FileKit
import SwiftUI

/// One inspector for any selection (R10): totals measured now, kinds, place,
/// dates, editable tags and comment, and the selection's actions.
struct InspectorView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @State private var summary: SelectionSummary?
    @State private var tagText = ""
    @State private var comment = ""

    var body: some View {
        let selection = pane.selectedItems.filter { !$0.isInArchive }
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if let summary, !selection.isEmpty {
                    Text(InspectorRows.title(summary, single: selection.first))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.strong)
                        .lineLimit(2).truncationMode(.middle)
                    Text(InspectorRows.size(summary) + ", measured now")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.dim).lineLimit(1)
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    ForEach(InspectorRows.rows(summary, home: model.services.paths.home), id: \.self) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label).font(.system(size: 11)).foregroundStyle(palette.faint).frame(width: 64, alignment: .leading)
                            Text(row.value).font(.system(size: 12)).foregroundStyle(palette.text).lineLimit(2).truncationMode(.middle)
                        }
                    }
                    field("Tags", text: $tagText, prompt: "Add tags, comma separated") {
                        model.setCommonTags(from: summary.commonTags, to: TagEditor.parse(tagText))
                    }
                    if selection.count == 1 {
                        field("Comment", text: $comment, prompt: "Spotlight comment") {
                            try? FinderComment.write(comment, to: selection[0].url)
                        }
                    }
                    Rectangle().fill(palette.hairline).frame(height: 1)
                    Text("Actions").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.faint)
                    ForEach([BrowserCommand.compress, .duplicate, .makeAlias, .copyPath, .share, .openClaude], id: \.self) { command in
                        actionRow(command)
                    }
                } else {
                    Text(selection.isEmpty ? "Select items to see their details" : "Measuring…")
                        .font(.system(size: 12)).foregroundStyle(palette.faint)
                }
            }
            .padding(14)
        }
        .background(palette.panel)
        .task(id: selection.map(\.id).joined(separator: "\n")) {
            summary = nil
            guard !selection.isEmpty else { return }
            let made = await SelectionSummary.make(for: selection.map(\.url), sizes: model.services.folderSizes)
            summary = made
            tagText = made.commonTags.joined(separator: ", ")
            comment = selection.count == 1 ? FinderComment.read(selection[0].url) : ""
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.faint)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(palette.field))
                .onSubmit(commit)
        }
    }

    private func actionRow(_ command: BrowserCommand) -> some View {
        Button { model.perform(command) } label: {
            HStack(spacing: 6) {
                Text(model.title(for: command)).font(.system(size: 12)).foregroundStyle(palette.text).lineLimit(1)
                Spacer(minLength: 6)
                if let shortcut = CommandCatalog.spec(command).shortcuts.first {
                    KeyCap(text: shortcut.description, palette: palette)
                }
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled(command))
    }
}
