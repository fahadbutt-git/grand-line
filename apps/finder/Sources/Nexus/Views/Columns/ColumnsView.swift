import AppKit
import BrowserKit
import SwiftUI

/// The column view: one column per folder from where it started down to the
/// pane's folder, each as wide as its longest name (R7). The last column is the
/// pane itself, so its selection drives every command. The other columns come
/// from `ColumnListings`, which reads each folder once and follows FSEvents.
struct ColumnsView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    @StateObject private var listings = ColumnListings()

    var body: some View {
        let chain = folders
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(chain, id: \.self) { (folder: URL) in
                        column(for: folder, in: chain)
                        Rectangle().fill(palette.hairline).frame(width: 1)
                    }
                    if pane.selectedItems.count == 1, let item = pane.selectedItems.first, !item.isFolder {
                        PreviewPane(pane: pane, palette: palette).frame(width: 300).id("preview")
                    }
                }
            }
            .onChange(of: chain.count) { _, _ in
                if let last = chain.last { withAnimation { reader.scrollTo(last, anchor: .trailing) } }
            }
        }
        .onAppear { listings.track(Array(chain.dropLast()), hidden: model.showHidden) }
        .onChange(of: chain) { _, new in listings.track(Array(new.dropLast()), hidden: model.showHidden) }
        .onChange(of: model.showHidden) { _, hidden in listings.track(Array(folders.dropLast()), hidden: hidden) }
        .onDisappear { listings.stop() }
        .modifier(BrowserKeys(model: model, pane: pane, rowStep: 1))
        .background(palette.background)
    }

    /// The columns: from the column root to the pane's folder.
    private var folders: [URL] {
        guard let current = pane.location.folderURL?.standardizedFileURL else { return [] }
        guard let root = pane.columnRoot?.standardizedFileURL,
              current.path == root.path || current.path.hasPrefix(root.path == "/" ? "/" : root.path + "/") else {
            return [current]
        }
        var chain: [URL] = [current]
        var cursor = current
        while cursor.path != root.path, cursor.path != "/" {
            cursor = cursor.deletingLastPathComponent()
            chain.insert(cursor, at: 0)
        }
        return chain
    }

    /// One column: the pane's own rows for the last folder, the cached listing
    /// for the folders above it, with the folder below highlighted.
    private func column(for folder: URL, in chain: [URL]) -> Column {
        let index: Int = chain.firstIndex(of: folder) ?? 0
        let isLast: Bool = index == chain.count - 1
        let items: [FileItem] = isLast ? pane.items : (listings.items[folder] ?? [])
        let chosen: String? = isLast ? nil : chain[index + 1].standardizedFileURL.path
        let selection: SelectionModel = pane.state.selection
        let isSelected: (FileItem) -> Bool = { item in
            isLast ? selection.contains(item.id) : item.url.standardizedFileURL.path == chosen
        }
        return Column(
            items: items, width: listings.width(of: items, in: folder), palette: palette,
            isSelected: isSelected, choose: { item in choose(item, isLast: isLast) },
            model: model, pane: pane, interactive: isLast
        )
    }

    private func choose(_ item: FileItem, isLast: Bool) {
        if pane.columnRoot == nil { pane.columnRoot = pane.location.folderURL }
        if item.isFolder {
            pane.go(.folder(item.url))
        } else if !isLast {
            pane.go(.folder(item.url.deletingLastPathComponent()), select: [item.url])
        } else {
            pane.select(ids: [item.id])
        }
    }
}

private struct Column: View {
    let items: [FileItem]
    let width: CGFloat
    let palette: Palette
    let isSelected: (FileItem) -> Bool
    let choose: (FileItem) -> Void
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let interactive: Bool

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: width)
    }

    @ViewBuilder private func row(_ item: FileItem) -> some View {
        let selected = isSelected(item)
        let base = HStack(spacing: 6) {
            Image(systemName: FileSymbol.name(for: item))
                .font(.system(size: 12))
                .foregroundStyle(item.isFolder ? palette.accent : palette.dim)
                .frame(width: 18)
            Text(item.shownName(allExtensions: NexusPreferencesStore.shared.current.showAllExtensions))
                .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(selected ? palette.selectionText : palette.text)
            Spacer(minLength: 4)
            if item.isFolder {
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(palette.faint)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? palette.selection : Color.clear).padding(.horizontal, 4))
        .contentShape(Rectangle())
        if interactive {
            base.modifier(ItemInteraction(model: model, pane: pane, item: item))
                .simultaneousGesture(TapGesture().onEnded { if item.isFolder { choose(item) } })
        } else {
            base.onTapGesture { choose(item) }
        }
    }
}
