import BrowserKit
import SwiftUI

/// The path bar (R5): clickable folders, or a field after Cmd+Shift+G (Finder's
/// Go to Folder) that takes a path (Tab completes) or a folder name to find in
/// the index.
struct PathBarView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @FocusState private var focused: Bool
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
        TextField("Path or folder name", text: $model.pathText)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(palette.strong)
            .padding(.horizontal, 8)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit {
                if !model.commitPath(model.pathText, fuzzyMatch: matches.first) { NSSound.beep() }
            }
            .onExitCommand { model.editingPath = false }
            .onKeyPress(.tab) {
                if let completed = model.completePath(model.pathText) { model.pathText = completed }
                return .handled
            }
            .task(id: model.pathText) {
                try? await Task.sleep(nanoseconds: 120_000_000)
                matches = await model.folderMatches(model.pathText)
            }
            .popover(isPresented: .constant(model.editingPath && !matches.isEmpty && !model.pathText.contains("/")), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { url in
                        Button { model.commitPath(model.pathText, fuzzyMatch: url) } label: {
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
