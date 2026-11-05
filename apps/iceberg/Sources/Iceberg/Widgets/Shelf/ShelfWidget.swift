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
    @ObservedObject private var display = DisplayOptions.shared
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let motion = Motion.drop(reduceMotion: display.reduceMotion)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionCaption(text: "Shelf", count: shelf.entries.isEmpty ? nil : shelf.entries.count)
                Spacer(minLength: 4)
                if !shelf.entries.isEmpty {
                    Button(action: { withAnimation(motion) { shelf.clear() } }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(SymbolScale.accessory)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme.muted)
                    }
                    .buttonStyle(PanelButtonStyle(kind: .icon))
                    .help("Take everything off the shelf. The files stay where they are.")
                    .accessibilityLabel("Clear the shelf")
                    .transition(.opacity)
                }
            }
            if let note = shelf.note {
                Text(note)
                    .font(TypeScale.caption)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
            if shelf.entries.isEmpty {
                EmptyNote(text: shelf.isDropTargeted ? "Drop to keep it here." : "Drag files onto the notch to keep them here.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shelf.entries) { entry in
                            ShelfRow(shelf: shelf, entry: entry)
                                .transition(.materialise(anchor: .top, reduceMotion: display.reduceMotion))
                        }
                    }
                    .padding(.vertical, ScrollEdgeFade.depth)
                }
                .padding(.vertical, -ScrollEdgeFade.depth)
                // Rows fade under the top and bottom edges rather than being cut.
                .mask { ScrollEdgeFade() }
            }
        }
        .padding(4)
        .background {
            // The drop target: a quiet fill and a dashed edge while a file is over the panel.
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape.fill(theme.highlight.opacity(0.08))
                .overlay(shape.strokeBorder(theme.highlight,
                                            style: StrokeStyle(lineWidth: 2 * PixelGrid.hairline(scale: displayScale), dash: [4, 3])))
                .opacity(shelf.isDropTargeted ? 1 : 0)
                .scaleEffect(shelf.isDropTargeted || display.reduceMotion ? 1 : 0.98)
        }
        .animation(motion, value: shelf.entries.map(\.id))
        .animation(Motion.hover, value: shelf.note)
    }
}

/// A vertical mask that fades the first and last few points of a list, so
/// rows slide under the edge.
/// The list is inset by the same depth, so at rest no row is faded.
struct ScrollEdgeFade: View {
    static let depth: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: Self.depth)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Self.depth)
        }
    }
}

/// One file: its icon and name (drag it out, double-click to open,
/// right-click for its menu), and a button for the same menu. The row
/// lights on hover and darkens on mouse-down, as Finder's do.
struct ShelfRow: View {
    @ObservedObject var shelf: ShelfModel
    let entry: ShelfModel.Entry
    @EnvironmentObject var theme: ThemeStore
    @ObservedObject private var display = DisplayOptions.shared
    @Environment(\.displayScale) private var displayScale
    @Local private var hovering = false
    @Local private var pressed = false

    var body: some View {
        let icon = shelf.icon(for: entry)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                    .opacity(entry.missing ? 0.5 : 1)
                Text(entry.item.name)
                    .font(TypeScale.callout)
                    .foregroundStyle(entry.missing ? theme.muted : theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(
                DragOutArea(url: entry.url, icon: icon,
                            onDoubleClick: { if let url = entry.url { NSWorkspace.shared.open(url) } },
                            menu: { shelf.menu(for: entry) },
                            onPress: { down in
                                if down {
                                    pressed = true
                                } else {
                                    withAnimation(Motion.spring(MotionSpec.release)) { pressed = false }
                                }
                            })
            )
            .help(entry.missing ? "\(entry.item.name) cannot be found (it was at \(entry.item.path))" : entry.item.path)
            if shelf.working.contains(entry.id) {
                ProgressView().controlSize(.mini)
            }
            Button(action: { shelf.popUpMenu(for: entry) }) {
                Image(systemName: "ellipsis.circle")
                    .font(SymbolScale.row)
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(PanelButtonStyle(kind: .icon))
            .opacity(hovering ? 1 : 0.6)
            .help("Actions")
            .accessibilityLabel("Actions for \(entry.item.name)")
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(
            shape.fill(hovering || pressed ? theme.selection : theme.card)
                .overlay(shape.fill(theme.foreground.opacity(pressed ? 0.06 : 0)))
                .overlay {
                    if display.increaseContrast {
                        shape.strokeBorder(theme.strongLine, lineWidth: PixelGrid.hairline(scale: displayScale))
                    }
                }
        )
        .onHover { inside in
            guard inside != hovering else { return }
            withAnimation(Motion.hover) { hovering = inside }
        }
    }
}
