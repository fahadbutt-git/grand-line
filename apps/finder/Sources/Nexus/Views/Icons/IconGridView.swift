import BrowserKit
import SwiftUI
import UniformTypeIdentifiers

/// The icon view: a thumbnail grid (R13). Cmd+= and Cmd+- change the size.
struct IconGridView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette
    let gallery: Bool

    var body: some View {
        let size = CGFloat(pane.state.settings.iconSize)
        let cell = size + 48
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - 16) / cell))
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    let items = pane.items
                    let inside = pane.state.insideFilesStart
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 4), count: columns), spacing: 6) {
                        ForEach(inside.map { Array(items[..<$0]) } ?? items) { item in
                            iconCell(item, size: size, width: cell)
                        }
                        // Search results by relevance: the files found only inside, under their header.
                        if let inside {
                            Section {
                                ForEach(Array(items[inside...])) { item in
                                    iconCell(item, size: size, width: cell)
                                }
                            } header: {
                                InsideFilesHeader(pane: pane, palette: palette)
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: pane.state.selection.cursor) { _, cursor in
                    if let cursor { reader.scrollTo(cursor) }
                }
            }
            .modifier(BrowserKeys(model: model, pane: pane, rowStep: columns))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let folder = pane.location.folderURL else { return false }
                FileDrop.load(providers) { model.drop($0, into: folder, forceCopy: NSEvent.modifierFlags.contains(.option)) }
                return true
            }
        }
        .background(palette.background)
    }

    private func iconCell(_ item: FileItem, size: CGFloat, width: CGFloat) -> some View {
        IconCell(item: item, size: size, selected: pane.state.selection.contains(item.id),
                 isCut: model.services.clipboard.isCut(item.url), palette: palette)
            .frame(width: width)
            .id(item.id)
            .modifier(ItemInteraction(model: model, pane: pane, item: item))
    }
}

/// "Found inside files (1,594)" over the files a search found only by what
/// is inside them, with Hide (the list view's header, for icons).
struct InsideFilesHeader: View {
    @ObservedObject var pane: PaneModel
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Text(ItemFormat.insideFilesHeader(pane.state.searchCounts?.insideFiles ?? 0))
                .font(NexusType.labelMedium)
                .foregroundStyle(palette.dim)
                .lineLimit(1)
                .fixedSize()
            Hairline(palette: palette)
            Button("Hide") { pane.setHidesInsideFiles(true) }
                .buttonStyle(LinkButtonStyle(palette: palette))
                .font(NexusType.label)
                .accessibilityLabel("Hide matches inside files")
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nexus.search.insideFilesHeader")
    }
}

struct IconCell: View {
    let item: FileItem
    let size: CGFloat
    let selected: Bool
    let isCut: Bool
    let palette: Palette

    var body: some View {
        VStack(spacing: 4) {
            Thumbnail(item: item, size: size, palette: palette)
                .padding(4)
                .background(SelectionFill(palette: palette, isSelected: selected, radius: 8))
            // The name sits on its own selection pill, as in Finder.
            Text(item.shownName(allExtensions: NexusPreferencesStore.shared.current.showAllExtensions))
                .font(NexusType.callout)
                .foregroundStyle(selected ? palette.selectionText : palette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(SelectionFill(palette: palette, isSelected: selected, radius: 4))
                .frame(height: 34, alignment: .top)
        }
        .opacity(isCut ? 0.45 : 1)
        .help(item.name)
    }
}
