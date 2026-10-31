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
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 4), count: columns), spacing: 6) {
                        ForEach(pane.items) { item in
                            IconCell(item: item, size: size, selected: pane.state.selection.contains(item.id),
                                     isCut: model.services.clipboard.isCut(item.url), palette: palette)
                                .frame(width: cell)
                                .id(item.id)
                                .modifier(ItemInteraction(model: model, pane: pane, item: item))
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
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? palette.selection : Color.clear))
            Text(item.shownName(allExtensions: NexusPreferencesStore.shared.current.showAllExtensions))
                .font(.system(size: 12))
                .foregroundStyle(selected ? palette.selectionText : palette.text)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)
        }
        .opacity(isCut ? 0.45 : 1)
        .help(item.name)
    }
}
