import AppKit
import SwiftUI
import IcebergKit

/// The shelf as a column of the open panel: files dropped on the notch,
/// newest first. Drag one out to any app (a copy; the original stays),
/// double-click to open it, or use its menu for the quick actions. The
/// list itself is `ShelfModel`, shared with the drop basket.
@MainActor
final class ShelfWidget: NotchWidget {
    let id = "shelf"
    let placement = WidgetPlacement.section
    private let shelf: ShelfModel

    init(context: WidgetContext) {
        shelf = context.shelf
    }

    func makeView() -> AnyView { AnyView(ShelfSectionView(shelf: shelf)) }

    func panelWillOpen() { shelf.refresh() }

    func panelDidClose() { shelf.isDropTargeted = false }
}

struct ShelfSectionView: View {
    @ObservedObject var shelf: ShelfModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionCaption(text: shelf.entries.isEmpty ? "Shelf" : "Shelf · \(shelf.entries.count)")
                Spacer(minLength: 4)
                if !shelf.entries.isEmpty {
                    Button(action: { shelf.clear() }) {
                        Image(systemName: "xmark.circle").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.muted)
                    .help("Take everything off the shelf. The files stay where they are.")
                }
            }
            if let note = shelf.note {
                Text(note).font(.system(size: 11)).foregroundStyle(theme.muted).lineLimit(1).truncationMode(.middle)
            }
            if shelf.entries.isEmpty {
                EmptyNote(text: shelf.isDropTargeted ? "Drop to keep it here." : "Drag files onto the notch to keep them here.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(shelf.entries) { entry in
                            ShelfRow(shelf: shelf, entry: entry)
                        }
                    }
                }
            }
        }
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.highlight, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .opacity(shelf.isDropTargeted ? 1 : 0)
        )
    }
}

/// One file: its icon and name (drag it out, double-click to open,
/// right-click for its menu), and a button for the same menu.
struct ShelfRow: View {
    @ObservedObject var shelf: ShelfModel
    let entry: ShelfModel.Entry
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let icon = shelf.icon(for: entry)
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                    .opacity(entry.missing ? 0.5 : 1)
                Text(entry.item.name)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.missing ? theme.muted : theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(
                DragOutArea(url: entry.url, icon: icon,
                            onDoubleClick: { if let url = entry.url { NSWorkspace.shared.open(url) } },
                            menu: { shelf.menu(for: entry) })
            )
            .help(entry.missing ? "\(entry.item.name) cannot be found (it was at \(entry.item.path))" : entry.item.path)
            if shelf.working.contains(entry.id) {
                ProgressView().controlSize(.mini)
            }
            Button(action: { shelf.popUpMenu(for: entry) }) {
                Image(systemName: "ellipsis.circle").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.muted)
            .help("Actions")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.card))
    }
}
