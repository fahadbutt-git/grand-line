import BrowserKit
import SwiftUI

/// The gallery view: a large preview of the selection over a strip of thumbnails.
struct GalleryView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            PreviewPane(pane: pane, palette: palette)
            Rectangle().fill(palette.hairline).frame(height: 1)
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(pane.items) { item in
                            Thumbnail(item: item, size: 72, palette: palette)
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(pane.state.selection.contains(item.id) ? palette.selection : Color.clear))
                                .id(item.id)
                                .help(item.name)
                                // One image per item, named, as Finder's gallery strip reads.
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(item.name)
                                .accessibilityAddTraits(.isImage)
                                .modifier(ItemInteraction(model: model, pane: pane, item: item))
                        }
                    }
                    .padding(8)
                }
                .frame(height: 100)
                .onChange(of: pane.state.selection.cursor) { _, cursor in
                    if let cursor { reader.scrollTo(cursor) }
                }
            }
        }
        .modifier(BrowserKeys(model: model, pane: pane, rowStep: 1))
        .background(palette.background)
        // Finder's gallery always previews something: the first item until
        // another is chosen, not "No selection" over the strip.
        .task(id: pane.items.first?.id ?? "") {
            if pane.state.selection.isEmpty, let first = pane.items.first { pane.select(ids: [first.id]) }
        }
    }
}
