import BrowserKit
import SwiftUI

/// One pane, or in the panes view 2 to 4 of them side by side or in a 2 by 2
/// grid (R12, R27). The focused pane has an accent line on top.
struct PaneArea: View {
    @ObservedObject var model: BrowserModel
    let palette: Palette

    var body: some View {
        let panes = model.visiblePanes
        if model.mode == .panes, panes.count > 1 {
            let grid = model.layout.grid
            VStack(spacing: 0) {
                ForEach(0..<grid.rows, id: \.self) { row in
                    if row > 0 { Hairline(palette: palette) }
                    HStack(spacing: 0) {
                        ForEach(0..<grid.columns, id: \.self) { column in
                            let index = row * grid.columns + column
                            if index < panes.count {
                                if column > 0 { Hairline(palette: palette, axis: .vertical) }
                                PaneView(model: model, pane: panes[index], palette: palette, showsHeader: true,
                                         isFocused: index == model.layout.focused)
                            }
                        }
                    }
                }
            }
        } else {
            PaneView(model: model, pane: model.focused, palette: palette, showsHeader: false, isFocused: true)
        }
    }
}

struct PaneView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    let showsHeader: Bool
    let isFocused: Bool
    /// The spinner shows only for a load that takes a while, so a quick
    /// folder never flashes it.
    @Local private var slowLoad = false

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            ZStack {
                content
                if let problem = pane.problem {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(NexusType.emptySymbol)
                            .foregroundStyle(palette.faint)
                            .accessibilityHidden(true)
                        Text(problem).font(NexusType.body).foregroundStyle(palette.dim)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else if !pane.isLoading, pane.items.isEmpty {
                    emptyState
                } else if pane.isLoading, pane.items.isEmpty, slowLoad {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading")
                }
            }
            .task(id: pane.isLoading) {
                slowLoad = false
                guard pane.isLoading else { return }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if !Task.isCancelled { slowLoad = pane.isLoading }
            }
            // Always the whole area under the toolbar, whatever the view inside
            // measures: a view with no height of its own would otherwise shrink
            // the pane to nothing and pull the toolbar down to the middle.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // One element for the whole area. Without it the identifier lands
            // on each child instead, so an empty Recents or search reported its
            // 16 pt "Empty folder" line as the file area.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nexus.pane")
            if case .search = pane.location {
                DriveResultsSection(pane: pane, account: GoogleDriveAccount.shared, palette: palette,
                                    home: model.services.paths.home)
            }
        }
        .background(isFocused || !showsHeader ? palette.background : palette.panel.opacity(0.5))
        // The pane takes the keys on mouse-down, before the click lands.
        .onPress { model.focus(pane) }
    }

    @ViewBuilder private var emptyState: some View {
        let empty = PaneEmptyState.make(for: pane.location, folderTitle: searchFolderTitle)
        VStack(spacing: 10) {
            Image(systemName: emptySymbol)
                .font(NexusType.emptySymbol)
                .foregroundStyle(palette.faint.opacity(0.8))
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(empty.message).font(NexusType.body).foregroundStyle(palette.faint)
                if let wider = empty.widen, case .search(let query, _) = pane.location {
                    Button(empty.widenTitle) { pane.replace(.search(query: query, scope: wider)) }
                        .buttonStyle(LinkButtonStyle(palette: palette))
                        .font(NexusType.body)
                        .accessibilityIdentifier("nexus.empty.widen")
                }
            }
        }
        .padding(24)
    }

    private var emptySymbol: String {
        switch pane.location {
        case .search: return "magnifyingglass"
        case .recents: return "clock"
        case .archive: return "doc.zipper"
        case .folder: return "folder"
        }
    }

    /// The folder a search started in, by the name its chip shows ("Trash").
    private var searchFolderTitle: String? {
        guard case .search(_, .folder(let path)) = pane.location else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        if url.path == model.services.paths.trash.standardizedFileURL.path { return "Trash" }
        return FileManager.default.displayName(atPath: url.path)
    }

    @ViewBuilder private var content: some View {
        switch model.mode == .panes ? ViewMode.list : model.mode {
        case .icons: IconGridView(model: model, pane: pane, palette: palette, gallery: false)
        case .gallery: GalleryView(model: model, pane: pane, palette: palette)
        // Columns follow folders; search results, Recents and archives have
        // none, so they show as a list there, as Finder does.
        case .columns where pane.location.folderURL == nil:
            FileListView(model: model, pane: pane, palette: palette, isFocused: isFocused)
        case .columns: ColumnsView(model: model, pane: pane, palette: palette)
        case .list, .panes: FileListView(model: model, pane: pane, palette: palette, isFocused: isFocused)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(headerPath).font(NexusType.label).foregroundStyle(palette.faint).lineLimit(1).truncationMode(.head)
            HStack(spacing: 6) {
                Image(systemName: pane.location.isArchive ? "doc.zipper" : "folder")
                    .font(NexusType.smallSymbol).foregroundStyle(isFocused ? palette.accent : palette.dim)
                Text(pane.location.title).font(NexusType.headline)
                    .foregroundStyle(isFocused ? palette.strong : palette.text).lineLimit(1).truncationMode(.middle)
                if pane.location.isArchive {
                    Text("nothing extracted yet").font(NexusType.label).foregroundStyle(palette.faint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(isFocused ? palette.accent : Color.clear).frame(height: 2) }
        .overlay(alignment: .bottom) { Hairline(palette: palette) }
    }

    private var headerPath: String {
        guard let folder = pane.location.diskFolder else { return "" }
        let base = pane.location.isArchive ? folder : folder.deletingLastPathComponent()
        return PathSegments.segments(for: base, home: model.services.paths.home, aliases: model.pathAliases)
            .map(\.title).joined(separator: " › ")
    }
}
